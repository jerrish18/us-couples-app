-- Only cron/postgres can scan private schedules. No app-callable privileged scheduler.
create function private.calendar_day(p_original date,p_year integer) returns date
language sql immutable set search_path='' as $$
 select make_date(p_year,extract(month from p_original)::integer,
 least(extract(day from p_original)::integer,
 extract(day from (make_date(p_year,extract(month from p_original)::integer,1)+interval '1 month - 1 day'))::integer));
$$;
revoke all on function private.calendar_day(date,integer) from public,anon,authenticated,service_role;

create function private.enqueue_reminders(p_now timestamptz default now()) returns integer
language plpgsql security definer set search_path='' as $$
declare r record; d record; local_now timestamp; due timestamptz; day date; span integer;
 title text; kind text; event_key text; inserted integer; total integer:=0;
begin
 for r in select c.id,c.together_since,p.user_id,
  case when exists(select 1 from pg_timezone_names t where t.name=p.timezone) then p.timezone else 'Asia/Kolkata' end zone,
  coalesce(n.reminders,true) reminders,coalesce(n.nudges,false) nudges
  from public.couples c join public.profiles p on p.couple_id=c.id
  left join public.notification_preferences n on n.user_id=p.user_id
  where c.partner_id is not null
 loop
  local_now:=p_now at time zone r.zone;
  if r.reminders then
   for d in select dt.* from public.dates dt where dt.couple_id=r.id
     and not exists(select 1 from public.date_responses s where s.date_id=dt.id and s.status='declined')
   loop
    foreach span in array array[24,1] loop
     due:=d.starts_at-make_interval(hours=>span);
     if due>p_now-interval '6 minutes' and due<=p_now then
      insert into private.push_outbox(couple_id,recipient_id,kind,payload,due_at,unique_key)
      values(r.id,r.user_id,'date_reminder',jsonb_build_object('title','A little time for us',
        'body',case when span=24 then 'Your date is tomorrow.' else 'Your date is in one hour.' end,
        'route','/calendar','kind','date_reminder','entity_id',d.id::text),p_now,
        'date:'||d.id||':'||r.user_id||':'||span||':'||d.starts_at::text) on conflict(unique_key) do nothing;
      get diagnostics inserted=row_count;total:=total+inserted;
     end if;
    end loop;
   end loop;
   for d in select a.id::text key,a.title,
      case when a.yearly then private.calendar_day(a.event_date,extract(year from local_now)::integer) else a.event_date end event_day
      from public.anniversaries a where a.couple_id=r.id
     union all
     select 'days-'||n, n||' days together',r.together_since+n from unnest(array[100,200,500,1000]) n where r.together_since is not null
     union all
     select 'years-'||n,n||case when n=1 then ' year together' else ' years together' end,
       (r.together_since+make_interval(years=>n))::date from generate_series(1,50) n where r.together_since is not null
   loop
    due:=(d.event_day+time '09:00') at time zone r.zone;
    if due>p_now-interval '6 minutes' and due<=p_now then
     insert into private.push_outbox(couple_id,recipient_id,kind,payload,due_at,unique_key)
     values(r.id,r.user_id,'anniversary_reminder',jsonb_build_object('title',d.title,
       'body','A special day for the two of you.','route','/calendar','kind','anniversary_reminder'),p_now,
       'anniversary:'||r.id||':'||d.key||':'||r.user_id||':'||d.event_day) on conflict(unique_key) do nothing;
     get diagnostics inserted=row_count;total:=total+inserted;
    end if;
   end loop;
  end if;
  if r.nudges then
   due:=(local_now::date+time '20:00') at time zone r.zone;
   if due>p_now-interval '6 minutes' and due<=p_now and not exists(
     select 1 from public.messages m where m.couple_id=r.id and m.created_at>=(local_now::date::timestamp at time zone r.zone) and m.created_at<=p_now) then
    insert into private.push_outbox(couple_id,recipient_id,kind,payload,due_at,unique_key)
    values(r.id,r.user_id,'nudge',jsonb_build_object('title','A little hello?',
     'body','If you feel like it, send your person a little love.','route','/chat','kind','nudge'),p_now,
     'nudge:'||r.id||':'||r.user_id||':'||local_now::date) on conflict(unique_key) do nothing;
    get diagnostics inserted=row_count;total:=total+inserted;
   end if;
  end if;
 end loop;
 return total;
end $$;
revoke all on function private.enqueue_reminders(timestamptz) from public,anon,authenticated,service_role;
select cron.schedule('us-scheduled-reminders','* * * * *','select private.enqueue_reminders();');
-- Bound cron's own history to keep free database space useful.
select cron.schedule('us-cron-history-cleanup','25 3 * * *','delete from cron.job_run_details where end_time<now()-interval ''7 days'';');
