-- Additive only. No existing rows, auth configuration or call policies change.
create table public.echo_preferences (
 couple_id uuid not null references public.couples(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 enabled boolean not null default false,
 rule text not null default 'manual' check(rule in('manual','always','schedule')),
 delay_seconds integer not null default 20 check(delay_seconds between 0 and 40),
 language text not null default 'English' check(language in('English','Tamil','Tanglish')),
 greeting text not null default '' check(length(greeting)<=300),
 voice text not null default 'default' check(voice in('default','soft','bright')),
 timezone text not null default 'Asia/Kolkata' check(length(timezone)<=80),
 start_minute integer not null default 0 check(start_minute between 0 and 1439),
 end_minute integer not null default 0 check(end_minute between 0 and 1439),
 retain_transcript boolean not null default false,
 primary key(couple_id,user_id)
);
create table public.echo_devices (
 user_id uuid primary key references auth.users(id) on delete cascade,
 heartbeat timestamptz not null default now(),
 ready boolean not null default false
);
create table public.echo_requests (
 call_id uuid primary key references public.calls(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
create table public.echo_sessions (
 call_id uuid primary key references public.calls(id) on delete cascade,
 callee_id uuid not null references auth.users(id) on delete cascade,
 state text not null default 'ai' check(state in('ai','human','ended')),
 transcript jsonb not null default '[]' check(jsonb_typeof(transcript)='array' and octet_length(transcript::text)<=200000),
 summary text not null default '' check(length(summary)<=6000),
 important text not null default '' check(length(important)<=6000),
 human_offer text check(length(human_offer)<100000),
 human_answer text check(length(human_answer)<100000),
 updated_at timestamptz not null default now()
);
alter table public.echo_preferences enable row level security;
alter table public.echo_devices enable row level security;
alter table public.echo_requests enable row level security;
alter table public.echo_sessions enable row level security;
revoke all on public.echo_preferences,public.echo_devices,public.echo_requests,public.echo_sessions from public,anon,authenticated;
grant select,insert,update,delete on public.echo_preferences,public.echo_devices to authenticated;
grant select,insert,delete on public.echo_requests to authenticated;
grant select,insert,delete on public.echo_sessions to authenticated;
grant update(state,transcript,summary,important,human_offer,human_answer,updated_at) on public.echo_sessions to authenticated;
create policy echo_preferences_own on public.echo_preferences for all to authenticated
 using(user_id=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)))
 with check(user_id=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)));
create policy echo_device_own on public.echo_devices for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy echo_request_own on public.echo_requests for all to authenticated
 using(user_id=(select auth.uid()) and exists(select 1 from public.calls c where c.id=call_id and c.callee_id=(select auth.uid())))
 with check(user_id=(select auth.uid()) and exists(select 1 from public.calls c where c.id=call_id and c.callee_id=(select auth.uid()) and c.state='ringing' and c.expires_at>now()));
create policy echo_session_read on public.echo_sessions for select to authenticated
 using(exists(select 1 from public.calls c where c.id=call_id and (select auth.uid()) in(c.caller_id,c.callee_id)));
create policy echo_session_insert on public.echo_sessions for insert to authenticated
 with check(callee_id=(select auth.uid()) and state='ai' and human_offer is null and human_answer is null and exists(select 1 from public.calls c where c.id=call_id and c.callee_id=(select auth.uid()) and c.state='ringing' and c.expires_at>now()));
create policy echo_session_update on public.echo_sessions for update to authenticated
 using(callee_id=(select auth.uid()) and exists(select 1 from public.calls c where c.id=call_id and c.callee_id=(select auth.uid())))
 with check(callee_id=(select auth.uid()) and exists(select 1 from public.calls c where c.id=call_id and c.callee_id=(select auth.uid())));
create policy echo_session_delete on public.echo_sessions for delete to authenticated using(callee_id=(select auth.uid()));
-- Atomic arbitration with a human Answer tap or a second bridge instance.
create function public.echo_answer(p_call uuid,p_answer text) returns boolean
language plpgsql security invoker set search_path='' as $$
declare c public.calls;begin
 select * into c from public.calls where id=p_call for update;
 if c.id is null or c.callee_id is distinct from auth.uid() or c.state<>'ringing' or c.expires_at<=now() then return false;end if;
 if not exists(select 1 from public.echo_preferences p where p.couple_id=c.couple_id and p.user_id=auth.uid() and p.enabled) then return false;end if;
 insert into public.echo_sessions(call_id,callee_id) values(c.id,c.callee_id);
 update public.calls set answer=p_answer,state='connecting' where id=c.id;
 return true;
end $$;
revoke all on function public.echo_answer(uuid,text) from public,anon,authenticated;
grant execute on function public.echo_answer(uuid,text) to authenticated;
create index echo_requests_user on public.echo_requests(user_id);
create index echo_sessions_callee on public.echo_sessions(callee_id);
-- Existing calls expire after at most 2 hours and their cascade removes transcripts
-- when the established 1-day call retention job runs. Users can erase them earlier.

-- Enforce opt-out in the database too: an in-flight speech task cannot restore
-- a transcript after erasure, even before the bridge's next preference poll.
create function private.guard_echo_retention() returns trigger
language plpgsql security invoker set search_path='' as $$begin
 if not exists(select 1 from public.echo_preferences p join public.calls c on c.couple_id=p.couple_id
   where c.id=new.call_id and p.user_id=new.callee_id and p.retain_transcript) then
  new.transcript='[]';new.summary='';new.important='';
 end if;
 return new;
end $$;
revoke all on function private.guard_echo_retention() from public,anon,authenticated;
create trigger echo_retention before insert or update on public.echo_sessions for each row execute function private.guard_echo_retention();
-- Reuse the existing FCM outbox without putting private conversation text in push.
create function private.enqueue_echo() returns trigger
language plpgsql security definer set search_path='' as $$
declare c public.calls;begin
 if auth.uid() is distinct from new.callee_id then raise exception 'Not allowed';end if;
 select * into c from public.calls where id=new.call_id and callee_id=new.callee_id;
 if c.id is null then raise exception 'Call not found';end if;
 insert into private.push_outbox(couple_id,recipient_id,kind,payload,unique_key)
 values(c.couple_id,c.callee_id,'message',jsonb_build_object('title','ECHO answered as AI','body','Open Us to take over or review the call.','kind','message','route','/chat','entity_id',c.id::text),'echo:'||c.id::text)
 on conflict(unique_key) do nothing;
 perform private.kick_push();return new;
end $$;
revoke all on function private.enqueue_echo() from public,anon,authenticated,service_role;
create trigger echo_answered_push after insert on public.echo_sessions for each row execute function private.enqueue_echo();
