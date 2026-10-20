begin;
insert into auth.users(id,email) values('10000000-0000-4000-8000-000000000001','us-v16-a@example.invalid'),('10000000-0000-4000-8000-000000000002','us-v16-b@example.invalid'),('10000000-0000-4000-8000-000000000003','us-v16-c@example.invalid');
insert into public.couples(id,owner_id,partner_id,name) values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','v1.6 tests');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
insert into public.expenses(id,couple_id,author_id,title,amount,spent_on,category,outing)values('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Dinner',450.50,current_date,'Food','Date night');
update public.expenses set category='Entertainment' where id='40000000-0000-4000-8000-000000000001';
insert into public.cycle_profiles(user_id,couple_id) values('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001');
insert into public.cycle_logs(id,user_id,couple_id,start_date,end_date,flow,mood,symptoms) values('50000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',current_date-10,current_date-6,'Medium','Okay',array['Cramps']);
do $$begin
 begin insert into public.cycle_logs(user_id,couple_id,start_date,end_date,flow,mood) values('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',current_date-8,current_date-5,'Medium','Okay');raise exception 'Overlapping period accepted';exception when check_violation then null;end;
end$$;
insert into public.calls(id,couple_id,caller_id,callee_id,offer)values('60000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','synthetic-offer');
do $$begin
 begin update public.calls set state='connecting',answer='forged' where id='60000000-0000-4000-8000-000000000001';raise exception 'Caller answered their own call';exception when raise_exception then if sqlerrm='Caller answered their own call' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$begin
 if exists(select 1 from public.cycle_logs where id='50000000-0000-4000-8000-000000000001') then raise exception 'Unshared cycle leaked to partner';end if;
 if (select count(*) from public.calls where id='60000000-0000-4000-8000-000000000001')<>1 then raise exception 'Partner cannot receive call';end if;
 update public.expenses set amount=1 where id='40000000-0000-4000-8000-000000000001';
 if (select amount from public.expenses where id='40000000-0000-4000-8000-000000000001')<>450.50 then raise exception 'Partner edited expense';end if;
end$$;
update public.calls set state='connecting',answer='synthetic-answer' where id='60000000-0000-4000-8000-000000000001';
insert into public.call_candidates(call_id,sender_id,candidate)values('60000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','{"candidate":"synthetic","sdpMid":"0","sdpMLineIndex":0}');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
update public.cycle_profiles set share_with_partner=true where user_id='10000000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$begin
 if (select count(*) from public.cycle_logs where id='50000000-0000-4000-8000-000000000001')<>1 then raise exception 'Sharing not applied';end if;
 update public.cycle_logs set notes='forged' where id='50000000-0000-4000-8000-000000000001';
 if (select notes from public.cycle_logs where id='50000000-0000-4000-8000-000000000001')<>'' then raise exception 'Partner edited cycle';end if;
end$$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
do $$declare t text;n integer;begin
 foreach t in array array['cycle_profiles','cycle_logs','calls','call_candidates','expenses']loop execute format('select count(*) from public.%I where %s',t,case when t='call_candidates' then 'call_id=''60000000-0000-4000-8000-000000000001''' else 'couple_id=''20000000-0000-4000-8000-000000000001''' end)into n;if n<>0 then raise exception 'Third account read %',t;end if;end loop;
 begin insert into public.calls(couple_id,caller_id,callee_id,offer)values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','intrusion');raise exception 'Third user called partner';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
update public.cycle_profiles set share_with_partner=false where user_id='10000000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$begin if exists(select 1 from public.cycle_logs where id='50000000-0000-4000-8000-000000000001')then raise exception 'Revoked cycle still accessible';end if;end$$;
update public.calls set state='ended' where id='60000000-0000-4000-8000-000000000001';
reset role;
delete from public.couples where id='20000000-0000-4000-8000-000000000001';
do $$begin if exists(select 1 from public.cycle_logs where id='50000000-0000-4000-8000-000000000001')or exists(select 1 from public.call_candidates where call_id='60000000-0000-4000-8000-000000000001')then raise exception 'Deletion left health or calling data';end if;end$$;
rollback;
select 'PASS: expense owner editing, cycle opt-in sharing/revocation, overlap rejection, call roles and candidates, third-user isolation and cascade deletion' result;
