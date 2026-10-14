-- Membership can only change through authenticated, transactional pairing RPCs.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;
create table public.couples (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  partner_id uuid references auth.users(id) on delete restrict,
  name text not null default 'Us' check (char_length(name) between 1 and 60),
  together_since date,
  created_at timestamptz not null default now(),
  check (owner_id is distinct from partner_id)
);
create index couples_owner_idx on public.couples(owner_id);
create index couples_partner_idx on public.couples(partner_id);
create table private.invites (
  code text primary key check (code ~ '^[0-9A-F]{6}$'),
  couple_id uuid not null unique references public.couples(id) on delete cascade
);
create table private.join_attempts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_start timestamptz not null,
  attempts integer not null default 0
);
alter table private.invites enable row level security;
alter table private.join_attempts enable row level security;
revoke all on private.invites, private.join_attempts from public, anon, authenticated;
alter table public.couples enable row level security;
revoke all on public.couples from public, anon, authenticated;
grant select on public.couples to authenticated;
grant update (name, together_since) on public.couples to authenticated;
create policy couple_read on public.couples for select to authenticated
using ((select auth.uid()) in (owner_id, partner_id));
create policy couple_edit on public.couples for update to authenticated
using ((select auth.uid()) in (owner_id, partner_id))
with check ((select auth.uid()) in (owner_id, partner_id));

create function private.create_couple(p_name text, p_since date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); cid uuid; invite text;
begin
  if uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));
  if exists (select 1 from public.couples where uid in (owner_id, partner_id)) then
    raise exception 'You already belong to a couple space' using errcode = '23505';
  end if;
  insert into public.couples(owner_id, name, together_since)
  values (uid, trim(p_name), p_since) returning id into cid;
  loop
    invite := upper(encode(extensions.gen_random_bytes(3), 'hex'));
    begin
      insert into private.invites(code, couple_id) values (invite, cid);
      exit;
    exception when unique_violation then null;
    end;
  end loop;
  return jsonb_build_object('couple_id', cid, 'invite_code', invite);
end $$;
revoke all on function private.create_couple(text,date) from public, anon;
grant execute on function private.create_couple(text,date) to authenticated;
create function public.create_couple(p_name text default 'Us', p_since date default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.create_couple(p_name,p_since); $$;
revoke all on function public.create_couple(text,date) from public, anon;
grant execute on function public.create_couple(text,date) to authenticated;

-- Return errors rather than raise for invalid codes so failed attempts are committed.
create function private.join_couple(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); cid uuid; row_data public.couples; attempt_count integer;
begin
  if uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));
  if exists (select 1 from public.couples where uid in (owner_id, partner_id)) then
    return jsonb_build_object('error', 'already_paired');
  end if;
  insert into private.join_attempts as a(user_id,window_start,attempts) values(uid,now(),1)
  on conflict(user_id) do update set
    window_start = case when a.window_start < now()-interval '15 minutes' then now() else a.window_start end,
    attempts = case when a.window_start < now()-interval '15 minutes' then 1 else a.attempts+1 end
  returning attempts into attempt_count;
  if attempt_count > 5 then return jsonb_build_object('error','try_later'); end if;
  select couple_id into cid from private.invites where code=upper(trim(p_code));
  if cid is null then return jsonb_build_object('error','invalid_or_locked'); end if;
  select * into row_data from public.couples where id=cid for update;
  if row_data.id is null or row_data.partner_id is not null then
    return jsonb_build_object('error','invalid_or_locked');
  end if;
  update public.couples set partner_id=uid where id=cid;
  -- No member removal RPC; once partner_id is assigned there is no vacant slot.
  delete from private.invites where couple_id=cid;
  return jsonb_build_object('couple_id',cid);
end $$;
revoke all on function private.join_couple(text) from public, anon;
grant execute on function private.join_couple(text) to authenticated;
create function public.join_couple(p_code text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.join_couple(p_code); $$;
revoke all on function public.join_couple(text) from public, anon;
grant execute on function public.join_couple(text) to authenticated;

create function private.get_invite()
returns text language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); result text;
begin
  if uid is null then raise exception 'Sign in first' using errcode='42501'; end if;
  select i.code into result from private.invites i join public.couples c on c.id=i.couple_id
    where c.owner_id=uid and c.partner_id is null;
  return result;
end $$;
revoke all on function private.get_invite() from public, anon;
grant execute on function private.get_invite() to authenticated;
create function public.get_invite()
returns text language sql security invoker set search_path=''
as $$ select private.get_invite(); $$;
revoke all on function public.get_invite() from public, anon;
grant execute on function public.get_invite() to authenticated;
