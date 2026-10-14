
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
create table private.push_outbox (
 id uuid primary key default gen_random_uuid(),
 couple_id uuid not null references public.couples(id) on delete cascade,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 kind text not null,
 payload jsonb not null,
 due_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 delivered_at timestamptz,
 lease_until timestamptz,
 attempts integer not null default 0,
 unique_key text unique
);
alter table private.push_outbox enable row level security;
revoke all on private.push_outbox from public,anon,authenticated;
grant usage on schema private to service_role;
grant select,insert,update,delete on private.push_outbox to service_role;
create index push_pending_idx on private.push_outbox(due_at) where delivered_at is null;

create function private.push_config() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object(
   'account',(select decrypted_secret::jsonb from vault.decrypted_secrets where name='us_fcm_service_account'),
   'worker_key',(select decrypted_secret from vault.decrypted_secrets where name='us_push_worker_key'));
$$;
revoke all on function private.push_config() from public,anon,authenticated;
grant execute on function private.push_config() to service_role;
create function public.push_config() returns jsonb language sql security invoker set search_path=''
as $$ select private.push_config(); $$;
revoke all on function public.push_config() from public,anon,authenticated;
grant execute on function public.push_config() to service_role;

create function private.claim_pushes() returns setof private.push_outbox
language sql security definer set search_path='' as $$
 update private.push_outbox o set lease_until=now()+interval '3 minutes', attempts=attempts+1
 where o.id in (select p.id from private.push_outbox p
   where p.delivered_at is null and p.due_at<=now() and (p.lease_until is null or p.lease_until<now())
   and p.attempts<8 order by p.due_at limit 30 for update skip locked)
 returning o.*;
$$;
revoke all on function private.claim_pushes() from public,anon,authenticated;
grant execute on function private.claim_pushes() to service_role;
create function public.claim_pushes() returns setof private.push_outbox
language sql security invoker set search_path='' as $$ select * from private.claim_pushes(); $$;
revoke all on function public.claim_pushes() from public,anon,authenticated;
grant execute on function public.claim_pushes() to service_role;

create function private.finish_push(p_id uuid,p_success boolean) returns void
language sql security definer set search_path='' as $$
 update private.push_outbox set
 delivered_at=case when p_success then now() else delivered_at end,
 lease_until=case when p_success then null else now()+interval '5 minutes' end where id=p_id;
$$;
revoke all on function private.finish_push(uuid,boolean) from public,anon,authenticated;
grant execute on function private.finish_push(uuid,boolean) to service_role;
create function public.finish_push(p_id uuid,p_success boolean) returns void
language sql security invoker set search_path='' as $$ select private.finish_push(p_id,p_success); $$;
revoke all on function public.finish_push(uuid,boolean) from public,anon,authenticated;
grant execute on function public.finish_push(uuid,boolean) to service_role;

create function private.kick_push(p_health boolean default false) returns bigint
language sql security definer set search_path='' as $$
 select net.http_post(
 url:='https://mrtwyopmhmozuawgkuwi.supabase.co/functions/v1/push-worker',
 headers:=jsonb_build_object('Content-Type','application/json','x-worker-key',
 (select decrypted_secret from vault.decrypted_secrets where name='us_push_worker_key')),
 body:=jsonb_build_object('health',p_health), timeout_milliseconds:=15000);
$$;
revoke all on function private.kick_push(boolean) from public,anon,authenticated,service_role;

create function private.enqueue_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare c public.couples; who uuid; recipient uuid; kind text; payload jsonb; eid uuid;
begin
 select * into c from public.couples where id=new.couple_id;
 if c.partner_id is null then return new; end if;
 who:=case when tg_table_name in ('messages','miss_me') then (to_jsonb(new)->>'sender_id')::uuid
   when tg_table_name='date_responses' then new.user_id else (to_jsonb(new)->>'author_id')::uuid end;
 recipient:=case when who=c.owner_id then c.partner_id else c.owner_id end;
 kind:=case tg_table_name when 'messages' then 'message' when 'miss_me' then 'miss_me'
   when 'dates' then 'date_invite' else 'date_response' end;
 eid:=case when tg_table_name='date_responses' then new.date_id else (to_jsonb(new)->>'id')::uuid end;
 payload:=jsonb_build_object('title',case kind when 'miss_me' then 'Your person misses you ❤️'
   when 'message' then 'A message from your person' when 'date_invite' then 'A date, just for us'
   else 'Your person replied to your date' end,
   'body',case kind when 'miss_me' then 'Tap to send some love back.'
   when 'message' then 'Open Us to read it.' else 'Open Us to see the details.' end,
   'route',case when kind='message' then '/chat' when kind='miss_me' then '/' else '/calendar' end,
   'entity_id',eid::text,'kind',kind);
 insert into private.push_outbox(couple_id,recipient_id,kind,payload) values(c.id,recipient,kind,payload);
 perform private.kick_push();
 return new;
end $$;
revoke all on function private.enqueue_event() from public,anon,authenticated,service_role;
create trigger message_push after insert on public.messages for each row execute function private.enqueue_event();
create trigger miss_me_push after insert on public.miss_me for each row execute function private.enqueue_event();
create trigger date_push after insert on public.dates for each row execute function private.enqueue_event();
create trigger date_response_push after insert or update on public.date_responses for each row execute function private.enqueue_event();
-- Service reads through the explicit API grants; no privileged key is sent to an app.
grant select on public.device_tokens,public.notification_preferences,public.profiles,public.couples to service_role;
grant delete on public.device_tokens to service_role;
select cron.schedule('us-push-retry','* * * * *','select private.kick_push();');
select cron.schedule('us-push-cleanup','15 3 * * *',$job$
 delete from private.push_outbox where created_at<now()-interval '14 days';
 delete from private.join_attempts where window_start<now()-interval '1 day';
$job$);


create function private.defer_push(p_id uuid,p_until timestamptz) returns void language sql security definer set search_path='' as $$
 update private.push_outbox set lease_until=p_until,attempts=greatest(attempts-1,0) where id=p_id;
$$;
revoke all on function private.defer_push(uuid,timestamptz) from public,anon,authenticated;
grant execute on function private.defer_push(uuid,timestamptz) to service_role;
create function public.defer_push(p_id uuid,p_until timestamptz) returns void language sql security invoker set search_path=''
as $$ select private.defer_push(p_id,p_until); $$;
revoke all on function public.defer_push(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.defer_push(uuid,timestamptz) to service_role;
