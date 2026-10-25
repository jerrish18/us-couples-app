begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000011'),('00000000-0000-0000-0000-000000000012'),('00000000-0000-0000-0000-000000000013');
insert into public.couples(id,owner_id,partner_id) values ('10000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000012');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',true);
insert into public.calls(id,couple_id,caller_id,callee_id,offer) values ('20000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000012','offer');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000012',true);
insert into public.echo_preferences(couple_id,user_id,enabled,host) values ('10000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000012',true,'phone');
do $$begin
 if public.echo_answer('20000000-0000-0000-0000-000000000011','bridge answer') then raise exception 'Mac stole a phone-hosted call';end if;
 if not public.echo_answer_phone('20000000-0000-0000-0000-000000000011','phone answer') then raise exception 'Phone could not answer';end if;
 if (select host from public.echo_sessions where call_id='20000000-0000-0000-0000-000000000011')<>'phone' then raise exception 'Wrong answer host';end if;
 if public.echo_answer_phone('20000000-0000-0000-0000-000000000011','duplicate') then raise exception 'Duplicate phone answer';end if;
end$$;
update public.echo_sessions set state='human' where call_id='20000000-0000-0000-0000-000000000011';
do $$begin
 if (select answer from public.calls where id='20000000-0000-0000-0000-000000000011')<>'phone answer' then raise exception 'Takeover replaced original SDP';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000013',true);
do $$begin
 if public.echo_answer_phone('20000000-0000-0000-0000-000000000011','outsider') then raise exception 'Outsider claimed phone call';end if;
 update public.echo_sessions set host='bridge';if found then raise exception 'Outsider changed phone host';end if;
 if (select count(*) from public.echo_sessions)<>0 then raise exception 'Phone transcript leaked';end if;
end$$;
rollback;
