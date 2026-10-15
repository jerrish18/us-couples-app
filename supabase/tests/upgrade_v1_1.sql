begin;
-- Synthetic accounts exist only inside this rolled-back transaction.
insert into auth.users(id,email) values('10000000-0000-4000-8000-000000000001','us-test-a@example.invalid'),('10000000-0000-4000-8000-000000000002','us-test-b@example.invalid'),('10000000-0000-4000-8000-000000000003','us-test-c@example.invalid');
insert into public.couples(id,owner_id,partner_id,name) values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','Upgrade test');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.share_location('20000000-0000-4000-8000-000000000001',13.08,80.27,8,now()+interval '15 minutes');
select public.write_letter('20000000-0000-4000-8000-000000000001','Tomorrow','you need me','Secret future letter',now()+interval '1 day');
insert into public.messages(id,couple_id,sender_id,body)values('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Original');
select public.mutate_message('30000000-0000-4000-8000-000000000001','edit','Edited');
insert into public.expenses(couple_id,author_id,title,amount)values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Dinner',500);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$begin
 if (select count(*) from public.live_locations)<>1 then raise exception 'Partner cannot see location';end if;
 if exists(select 1 from public.letter_contents) then raise exception 'Future letter leaked';end if;
 if (select body from public.messages where id='30000000-0000-4000-8000-000000000001')<>'Edited' then raise exception 'Edit failed';end if;
 begin perform public.mutate_message('30000000-0000-4000-8000-000000000001','edit','Forged');raise exception 'Partner edited author message';exception when insufficient_privilege then null;end;
end$$;
select public.mutate_message('30000000-0000-4000-8000-000000000001','pin');
-- Stopping your own sharing never stops the other person's session.
select public.stop_location();
do $$begin if (select count(*) from public.live_locations)<>1 then raise exception 'Partner stopped someone else';end if;end$$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
do $$declare t text;n integer;begin
 foreach t in array array['live_locations','letters','letter_contents','expenses','polls','poll_votes','memory_collections','messages']loop
 execute format('select count(*) from public.%I',t)into n;if n<>0 then raise exception 'Third account read %',t;end if;
 end loop;
 begin perform public.share_location('20000000-0000-4000-8000-000000000001',1,1,1,now()+interval '15 minutes');raise exception 'Third account shared location';exception when insufficient_privilege then null;end;
 begin insert into public.expenses(couple_id,author_id,title,amount)values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003','Intrusion',1);raise exception 'Third account wrote expense';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.stop_location();
do $$begin if exists(select 1 from public.live_locations)then raise exception 'Stop did not revoke location';end if;end$$;
reset role;
insert into public.live_locations values('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',1,1,5,now()-interval '1 second',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$begin if exists(select 1 from public.live_locations)then raise exception 'Expired position leaked';end if;end$$;
reset role;
-- Collections and sealed letter contents cascade with their couple.
insert into public.memory_collections(id,couple_id,author_id,title)values('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Trip');
insert into public.memories(couple_id,author_id,media_path,caption,memory_date,collection_id)values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000001/test.jpg','Test',current_date,'40000000-0000-4000-8000-000000000001');
delete from public.couples where id='20000000-0000-4000-8000-000000000001';
do $$declare t text;n integer;begin foreach t in array array['live_locations','letters','letter_contents','expenses','memory_collections','memories']loop execute format('select count(*) from public.%I where couple_id=$1',t)into n using '20000000-0000-4000-8000-000000000001'::uuid;if n<>0 then raise exception 'Deletion left rows in %',t;end if;end loop;end$$;
rollback;
select 'PASS: third-user isolation, location consent identity/stop, timed-letter secrecy, own-message editing and shared pins' result;
