-- v1.7 AI: preferences are live-only; no chat is retained in usage counters.
create table public.ai_preferences (
  couple_id uuid not null references public.couples(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  share_history boolean not null default false,
  primary key(couple_id,user_id),
  check(not share_history or enabled)
);
alter table public.ai_preferences enable row level security;
revoke all on public.ai_preferences from public,anon,authenticated;
grant select,insert,update on public.ai_preferences to authenticated;
create policy ai_preferences_read on public.ai_preferences for select to authenticated using (
 exists(select 1 from public.couples c where c.id=couple_id and (select auth.uid()) in(c.owner_id,c.partner_id) and c.deleting_at is null));
create policy ai_preferences_insert on public.ai_preferences for insert to authenticated with check (
 user_id=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and (select auth.uid()) in(c.owner_id,c.partner_id) and c.deleting_at is null));
create policy ai_preferences_update on public.ai_preferences for update to authenticated using(user_id=(select auth.uid())) with check (
 user_id=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and (select auth.uid()) in(c.owner_id,c.partner_id) and c.deleting_at is null));
create table public.ai_answers (
 id uuid primary key default gen_random_uuid(),
 couple_id uuid not null references public.couples(id) on delete cascade,
 requested_by uuid not null references auth.users(id),
 prompt text not null check(length(prompt)<=1500),
 answer text not null check(length(answer)<=6000),
 sources jsonb not null default '[]',
 created_at timestamptz not null default now()
);
alter table public.ai_answers enable row level security;
revoke all on public.ai_answers from public,anon,authenticated;
grant select on public.ai_answers to authenticated;
create policy ai_answers_read on public.ai_answers for select to authenticated using (
 exists(select 1 from public.couples c where c.id=couple_id and (select auth.uid()) in(c.owner_id,c.partner_id) and c.deleting_at is null));
create index ai_answers_timeline on public.ai_answers(couple_id,created_at);
create table private.ai_usage (
 couple_id uuid not null references public.couples(id) on delete cascade,
 day date not null,
 requests integer not null default 0,
 last_request timestamptz,
 primary key(couple_id,day)
);
alter table private.ai_usage enable row level security;
revoke all on private.ai_usage from public,anon,authenticated;
-- Only the authenticated Edge handler's service role can reserve usage.
create function public.reserve_ai_request(p_couple uuid) returns boolean
language plpgsql security invoker set search_path='' as $$
declare n integer;begin
 insert into private.ai_usage(couple_id,day,requests,last_request) values(p_couple,(now() at time zone 'UTC')::date,1,now())
 on conflict(couple_id,day) do update set requests=private.ai_usage.requests+1,last_request=now()
 where private.ai_usage.requests<20 and private.ai_usage.last_request<now()-interval '30 seconds'
 returning requests into n;
 return n is not null;
end$$;
revoke all on function public.reserve_ai_request(uuid) from public,anon,authenticated;
grant usage on schema private to service_role;
grant select,insert,update on private.ai_usage to service_role;
grant execute on function public.reserve_ai_request(uuid) to service_role;
grant all on public.ai_answers to service_role;
grant select on public.ai_preferences to service_role;
