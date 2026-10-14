alter table public.couples add column deleting_at timestamptz;
create table private.deletion_jobs(couple_id uuid primary key references public.couples(id) on delete cascade,requested_at timestamptz not null default now());
alter table private.deletion_jobs enable row level security;
revoke all on private.deletion_jobs from public,anon,authenticated;
grant select,delete on private.deletion_jobs to service_role;

create function private.guard_space_writes() returns trigger language plpgsql security definer set search_path='' as $$
declare cid uuid;deleted timestamptz;
begin
 if tg_table_schema='storage' then
  if coalesce(to_jsonb(new)->>'bucket_id',to_jsonb(old)->>'bucket_id')<>'couple-media' then return coalesce(new,old);end if;
  cid:=split_part(coalesce(to_jsonb(new)->>'name',to_jsonb(old)->>'name'),'/',1)::uuid;
 elsif tg_table_name='couples' then cid:=coalesce(new.id,old.id);
 else cid:=coalesce((to_jsonb(new)->>'couple_id')::uuid,(to_jsonb(old)->>'couple_id')::uuid);end if;
 select deleting_at into deleted from public.couples where id=cid for key share;
 -- Storage API cleanup and the service-only final deletion must remain possible.
 if deleted is not null and current_setting('role',true) not in ('service_role','postgres') then
  raise exception 'This space is being deleted' using errcode='42501';
 end if;
 return coalesce(new,old);
end $$;
revoke all on function private.guard_space_writes() from public,anon,authenticated,service_role;
do $$ declare t text;begin
 foreach t in array array['profiles','messages','message_states','memories','reactions','dates','date_responses','anniversaries','list_items','love_notes','journal_entries','miss_me'] loop
  execute format('create trigger protect_deleting_space before insert or update or delete on public.%I for each row execute function private.guard_space_writes()',t);
 end loop;
end $$;
create trigger protect_deleting_space before update on public.couples for each row execute function private.guard_space_writes();
create trigger protect_deleting_space before insert or update on storage.objects for each row execute function private.guard_space_writes();

create function private.begin_space_delete(p_couple uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();c public.couples;
begin
 if uid is null then raise exception 'Sign in first' using errcode='42501';end if;
 select * into c from public.couples where id=p_couple for update;
 if c.id is null or uid not in(c.owner_id,coalesce(c.partner_id,c.owner_id)) then raise exception 'Access denied' using errcode='42501';end if;
 if c.deleting_at is null then update public.couples set deleting_at=now() where id=p_couple;end if;
 insert into private.deletion_jobs(couple_id) values(p_couple) on conflict do nothing;
 return p_couple;
end $$;
revoke all on function private.begin_space_delete(uuid) from public,anon;
grant execute on function private.begin_space_delete(uuid) to authenticated;
create function public.begin_space_delete(p_couple uuid) returns uuid language sql security invoker set search_path='' as $$ select private.begin_space_delete(p_couple); $$;
revoke all on function public.begin_space_delete(uuid) from public,anon;
grant execute on function public.begin_space_delete(uuid) to authenticated;

create function private.deletion_files(p_couple uuid) returns setof text language sql security definer set search_path='' as $$
 select o.name from storage.objects o where o.bucket_id='couple-media' and split_part(o.name,'/',1)=p_couple::text
 and exists(select 1 from private.deletion_jobs d where d.couple_id=p_couple) limit 500;
$$;
revoke all on function private.deletion_files(uuid) from public,anon,authenticated;
grant execute on function private.deletion_files(uuid) to service_role;
create function public.deletion_files(p_couple uuid) returns setof text language sql security invoker set search_path='' as $$ select * from private.deletion_files(p_couple); $$;
revoke all on function public.deletion_files(uuid) from public,anon,authenticated;
grant execute on function public.deletion_files(uuid) to service_role;

create function private.finish_space_delete(p_couple uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare c public.couples;
begin
 select * into c from public.couples where id=p_couple for update;
 if c.id is null then return true;end if;
 if c.deleting_at is null or not exists(select 1 from private.deletion_jobs where couple_id=p_couple) then raise exception 'Deletion not requested';end if;
 if exists(select 1 from storage.objects where bucket_id='couple-media' and split_part(name,'/',1)=p_couple::text) then return false;end if;
 delete from public.device_tokens where user_id in(c.owner_id,c.partner_id);
 delete from public.notification_preferences where user_id in(c.owner_id,c.partner_id);
 delete from public.couples where id=p_couple;
 return true;
end $$;
revoke all on function private.finish_space_delete(uuid) from public,anon,authenticated;
grant execute on function private.finish_space_delete(uuid) to service_role;
create function public.finish_space_delete(p_couple uuid) returns boolean language sql security invoker set search_path='' as $$ select private.finish_space_delete(p_couple); $$;
revoke all on function public.finish_space_delete(uuid) from public,anon,authenticated;
grant execute on function public.finish_space_delete(uuid) to service_role;
create function private.pending_deletions() returns setof uuid language sql security definer set search_path='' as $$ select couple_id from private.deletion_jobs order by requested_at limit 10; $$;
revoke all on function private.pending_deletions() from public,anon,authenticated;
grant execute on function private.pending_deletions() to service_role;
create function public.pending_deletions() returns setof uuid language sql security invoker set search_path='' as $$ select * from private.pending_deletions(); $$;
revoke all on function public.pending_deletions() from public,anon,authenticated;
grant execute on function public.pending_deletions() to service_role;
create function private.kick_deletions() returns bigint language sql security definer set search_path='' as $$
 select net.http_post(url:='https://mrtwyopmhmozuawgkuwi.supabase.co/functions/v1/delete-space',
 headers:=jsonb_build_object('Content-Type','application/json','x-worker-key',(select decrypted_secret from vault.decrypted_secrets where name='us_push_worker_key')),
 body:='{}'::jsonb,timeout_milliseconds:=15000) where exists(select 1 from private.deletion_jobs);
$$;
revoke all on function private.kick_deletions() from public,anon,authenticated,service_role;
select cron.schedule('us-delete-retry','*/5 * * * *','select private.kick_deletions();');
