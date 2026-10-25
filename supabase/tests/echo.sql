-- Run against a disposable database with the existing call schema and ECHO migration.
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003');
insert into public.couples(id,owner_id,partner_id) values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
insert into public.calls(id,couple_id,caller_id,callee_id,offer) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','offer');
do $$begin
 if public.echo_answer('20000000-0000-0000-0000-000000000001','answer') then raise exception 'Caller claimed callee call';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
insert into public.echo_preferences(couple_id,user_id,enabled,retain_transcript) values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',true,true);
insert into public.echo_requests(call_id,user_id) values ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');
do $$begin
 if not public.echo_answer('20000000-0000-0000-0000-000000000001','answer') then raise exception 'Callee could not answer';end if;
 if public.echo_answer('20000000-0000-0000-0000-000000000001','second answer') then raise exception 'Duplicate bridge claimed';end if;
 if (select state from public.calls where id='20000000-0000-0000-0000-000000000001')<>'connecting' then raise exception 'Call not connected atomically';end if;
end$$;
update public.echo_sessions set transcript='[{"role":"caller","text":"Call tomorrow"}]',human_offer='human offer' where call_id='20000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
do $$begin
 if (select count(*) from public.echo_sessions)<>1 then raise exception 'Caller cannot read own disclosure';end if;
 if (select count(*) from public.echo_preferences)<>0 then raise exception 'Partner settings leaked';end if;
 update public.echo_sessions set human_answer='forged answer';
 if found then raise exception 'Caller changed human answer';end if;
 begin
  insert into public.echo_preferences(couple_id,user_id,enabled) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',false);
  raise exception 'Partner changed callee preferences';
 exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
do $$begin
 if (select count(*) from public.echo_sessions)<>0 then raise exception 'Outsider read transcript';end if;
 if public.echo_answer('20000000-0000-0000-0000-000000000001','forged') then raise exception 'Outsider claimed call';end if;
 begin
  insert into public.echo_requests(call_id,user_id) values ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003');
  raise exception 'Outsider requested AI';
 exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
update public.echo_preferences set enabled=false,retain_transcript=false;
-- Simulate an old inference result arriving after erasure/opt-out.
update public.echo_sessions set transcript='[{"role":"caller","text":"stale result"}]',summary='stale result';
do $$begin
 if (select transcript from public.echo_sessions where call_id='20000000-0000-0000-0000-000000000001')<>'[]'::jsonb then raise exception 'In-flight result restored erased transcript';end if;
end$$;
update public.echo_sessions set transcript='[]',summary='',important='';
do $$begin
 if (select transcript from public.echo_sessions where call_id='20000000-0000-0000-0000-000000000001')<>'[]'::jsonb then raise exception 'Erasure failed';end if;
end$$;
rollback;
