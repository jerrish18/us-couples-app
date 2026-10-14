begin;
do $test$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();cid uuid;eid uuid:=gen_random_uuid();n integer;
 moment timestamptz:='2027-02-28 03:30:20+00';
begin
 insert into auth.users(id,email,aud,role) values(a,a||'@example.invalid','authenticated','authenticated'),(b,b||'@example.invalid','authenticated','authenticated');
 insert into public.couples(owner_id,partner_id,together_since) values(a,b,date '2026-02-28') returning id into cid;
 insert into public.dates(id,couple_id,author_id,title,starts_at) values(eid,cid,a,'Tomorrow',moment+interval '24 hours'-interval '20 seconds');
 insert into public.anniversaries(couple_id,author_id,title,event_date) values(cid,a,'Leap birthday',date '2024-02-29');
 delete from private.push_outbox where couple_id=cid;
 perform private.enqueue_reminders(moment);
 select count(*) into n from private.push_outbox where couple_id=cid;
 if n<>6 then raise exception 'FAIL: date, leap birthday and one-year milestone for each partner: got %',n;end if;
 perform private.enqueue_reminders(moment);
 if (select count(*) from private.push_outbox where couple_id=cid)<>6 then raise exception 'FAIL: duplicate scheduled reminders';end if;
 update public.dates set starts_at=moment+interval '1 hour'-interval '20 seconds' where id=eid;
 perform private.enqueue_reminders(moment);
 if (select count(*) from private.push_outbox where couple_id=cid and kind='date_reminder')<>4 then raise exception 'FAIL: one-hour reminders';end if;
 if has_function_privilege('authenticated','private.enqueue_reminders(timestamptz)','execute') then raise exception 'FAIL: client can scan reminders';end if;
 insert into public.notification_preferences(user_id,nudges,reminders) values(a,true,false),(b,false,false);
 delete from public.messages where couple_id=cid;
 perform private.enqueue_reminders('2027-02-28 14:30:20+00');
 if (select count(*) from private.push_outbox where couple_id=cid and kind='nudge')<>1 then raise exception 'FAIL: opt-in nudge';end if;
 raise notice 'PASS: date offsets, leap day, milestones, deduplication, opt-in nudge and scheduler privacy';
end $test$;
rollback;
