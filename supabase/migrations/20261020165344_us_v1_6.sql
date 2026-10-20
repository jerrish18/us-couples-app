begin;
alter table public.expenses add column spent_on date, add column category text not null default 'Other' check(category in ('Food','Travel','Shopping','Stay','Entertainment','Bills','Gifts','Other')),add column outing text check(length(outing)<=100),add column notes text check(length(notes)<=1000);
-- A legacy record has no known spending date: its creation date is retained.
update public.expenses set spent_on=(created_at at time zone 'Asia/Kolkata')::date;
alter table public.expenses alter column spent_on set default current_date,alter column spent_on set not null;
grant update(title,amount,currency,spent_on,category,outing,notes) on public.expenses to authenticated;
create policy own_update on public.expenses for update to authenticated using(author_id=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id))) with check(author_id=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)));
create index expenses_group_date on public.expenses(couple_id,spent_on desc);
alter table public.messages drop constraint messages_media_kind_check;
alter table public.messages add constraint messages_media_kind_check check(media_kind in ('photo','voice','file','video'));
alter table public.messages drop constraint messages_file_size_check;
alter table public.messages add constraint messages_file_size_check check(file_size between 0 and case when media_kind='video' then 52428800 else 5242880 end);
update storage.buckets set file_size_limit=52428800,allowed_mime_types=array(select distinct unnest(allowed_mime_types||array['video/mp4','video/quicktime','video/3gpp'])) where id='couple-media';

create table public.cycle_profiles(
 user_id uuid primary key references auth.users on delete cascade,
 couple_id uuid not null references public.couples on delete cascade,
 share_with_partner boolean not null default false,
 cycle_length integer not null default 28 check(cycle_length between 15 and 90),
 period_length integer not null default 5 check(period_length between 1 and 30),
 created_at timestamptz not null default now(),unique(user_id,couple_id)
);
create table public.cycle_logs(
 id uuid primary key default gen_random_uuid(),user_id uuid not null,couple_id uuid not null,
 start_date date not null,end_date date not null,
 flow text not null check(flow in ('Light','Medium','Heavy','Spotting')),
 mood text not null check(mood in ('Okay','Happy','Low','Sensitive','Anxious','Energetic')),
 symptoms text[] not null default '{}' check(symptoms <@ array['Cramps','Headache','Bloating','Fatigue','Backache','Tenderness','Acne']),
 notes text not null default '' check(length(notes)<=1000),created_at timestamptz not null default now(),
 foreign key(user_id,couple_id) references public.cycle_profiles(user_id,couple_id) on delete cascade,
 check(end_date>=start_date and end_date-start_date<=29 and end_date<=current_date),unique(user_id,start_date)
);
create index cycle_logs_owner_date on public.cycle_logs(user_id,start_date desc);
alter table public.cycle_profiles enable row level security;
alter table public.cycle_logs enable row level security;
revoke all on public.cycle_profiles,public.cycle_logs from anon,authenticated;
grant select,insert,delete on public.cycle_profiles,public.cycle_logs to authenticated;
grant update(share_with_partner,cycle_length,period_length) on public.cycle_profiles to authenticated;
grant update(start_date,end_date,flow,mood,symptoms,notes) on public.cycle_logs to authenticated;
create policy cycle_profile_read on public.cycle_profiles for select to authenticated using(exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)) and (user_id=(select auth.uid()) or share_with_partner));
create policy cycle_profile_insert on public.cycle_profiles for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)));
create policy cycle_profile_update on public.cycle_profiles for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)));
create policy cycle_profile_delete on public.cycle_profiles for delete to authenticated using(user_id=(select auth.uid()));
create policy cycle_log_read on public.cycle_logs for select to authenticated using(exists(select 1 from public.cycle_profiles p where p.user_id=cycle_logs.user_id and p.couple_id=cycle_logs.couple_id));
create policy cycle_log_insert on public.cycle_logs for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.cycle_profiles p join public.couples c on c.id=p.couple_id where p.user_id=cycle_logs.user_id and p.couple_id=cycle_logs.couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)));
create policy cycle_log_update on public.cycle_logs for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)));
create policy cycle_log_delete on public.cycle_logs for delete to authenticated using(user_id=(select auth.uid()));
create function private.cycle_no_overlap() returns trigger language plpgsql security invoker set search_path='' as $$begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text,0));
 if exists(select 1 from public.cycle_logs l where l.user_id=new.user_id and l.id<>new.id and l.start_date<=new.end_date and l.end_date>=new.start_date) then raise exception 'Period dates overlap an existing entry' using errcode='23514';end if;
 return new;end $$;
create trigger cycle_no_overlap before insert or update on public.cycle_logs for each row execute function private.cycle_no_overlap();

create table public.calls(
 id uuid primary key default gen_random_uuid(),couple_id uuid not null references public.couples on delete cascade,
 caller_id uuid not null references auth.users,callee_id uuid not null references auth.users,
 video boolean not null default false,offer text not null check(length(offer)<100000),answer text check(length(answer)<100000),
 state text not null default 'ringing' check(state in('ringing','connecting','connected','ended','declined','missed','failed')),
 created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '60 seconds',ended_at timestamptz,
 check(caller_id<>callee_id)
);
create unique index one_live_call_per_couple on public.calls(couple_id) where state in('ringing','connecting','connected');
create table public.call_candidates(
 id uuid primary key default gen_random_uuid(),call_id uuid not null references public.calls on delete cascade,
 sender_id uuid not null references auth.users,candidate jsonb not null check(octet_length(candidate::text)<8000),created_at timestamptz not null default now()
);
create index call_candidates_call on public.call_candidates(call_id,created_at);
alter table public.calls enable row level security;alter table public.call_candidates enable row level security;
revoke all on public.calls,public.call_candidates from anon,authenticated;
grant select,insert on public.calls,public.call_candidates to authenticated;
grant update(state,answer,ended_at) on public.calls to authenticated;
create policy call_read on public.calls for select to authenticated using((select auth.uid()) in(caller_id,callee_id) and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)));
create policy call_insert on public.calls for insert to authenticated with check(caller_id=(select auth.uid()) and state='ringing' and answer is null and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and ((caller_id=c.owner_id and callee_id=c.partner_id) or (caller_id=c.partner_id and callee_id=c.owner_id))));
create policy call_update on public.calls for update to authenticated using((select auth.uid()) in(caller_id,callee_id) and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id))) with check((select auth.uid()) in(caller_id,callee_id));
create policy candidate_read on public.call_candidates for select to authenticated using(exists(select 1 from public.calls c where c.id=call_id and (select auth.uid()) in(c.caller_id,c.callee_id)));
create policy candidate_insert on public.call_candidates for insert to authenticated with check(sender_id=(select auth.uid()) and exists(select 1 from public.calls c where c.id=call_id and c.state in('ringing','connecting','connected') and (select auth.uid()) in(c.caller_id,c.callee_id)));
create function private.guard_call() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if tg_op='INSERT' then
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.couple_id::text,1));
  update public.calls set state='missed',ended_at=now() where couple_id=new.couple_id and state in('ringing','connecting','connected') and expires_at<now();
  new.created_at=now();new.expires_at=now()+interval '60 seconds';new.ended_at=null;
 elsif old.state in('ended','declined','missed','failed') then raise exception 'Call has ended';
 elsif new.state='connecting' then
  if auth.uid()<>old.callee_id or old.state<>'ringing' or old.expires_at<now() or new.answer is null then raise exception 'Cannot answer this call';end if;
  new.expires_at=now()+interval '2 hours';
 elsif new.state='connected' then
  if old.state not in('connecting','connected') then raise exception 'Call is not connecting';end if;
 elsif new.state not in('ended','declined','missed','failed') then raise exception 'Invalid call transition';
 end if;
 if tg_op='UPDATE' and new.answer is distinct from old.answer and not(new.state='connecting' and old.state='ringing' and auth.uid()=old.callee_id) then raise exception 'Answer is immutable';end if;
 if new.state in('ended','declined','missed','failed') then new.ended_at=now();end if;
 return new;end $$;
create trigger guard_call before insert or update on public.calls for each row execute function private.guard_call();
alter publication supabase_realtime add table public.calls,public.call_candidates;
-- Ephemeral network candidates and SDP are removed after 24 hours.
select cron.schedule('us-expire-calls','*/5 * * * *',$$update public.calls set state='missed',ended_at=now() where state in('ringing','connecting','connected') and expires_at<now();delete from public.calls where created_at<now()-interval '1 day'$$);

-- Trigger-only bridge into the existing authenticated push worker.
create function private.enqueue_call() returns trigger language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is distinct from new.caller_id then raise exception 'Not allowed';end if;
 insert into private.push_outbox(couple_id,recipient_id,kind,payload,unique_key) values(new.couple_id,new.callee_id,'call',jsonb_build_object('title',case when new.video then 'Your person is video calling' else 'Your person is calling' end,'body','Open Us to answer.','kind','call','route','/chat','entity_id',new.id::text),'call:'||new.id::text);
 perform private.kick_push();return new;end $$;
revoke all on function private.enqueue_call() from public,anon,authenticated,service_role;
create trigger call_push after insert on public.calls for each row execute function private.enqueue_call();
commit;
