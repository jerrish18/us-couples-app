begin;
do $test$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();outsider uuid:=gen_random_uuid();cid uuid;blocked boolean:=false;
begin
 insert into auth.users(id,email,aud,role) values(a,a||'@example.invalid','authenticated','authenticated'),(b,b||'@example.invalid','authenticated','authenticated'),(outsider,outsider||'@example.invalid','authenticated','authenticated');
 insert into public.couples(owner_id,partner_id) values(a,b) returning id into cid;
 insert into public.messages(couple_id,sender_id,body) values(cid,a,'Private');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.begin_space_delete(cid);exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'FAIL: outsider can delete';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 perform public.begin_space_delete(cid);
 perform public.begin_space_delete(cid); -- retry is idempotent
 blocked:=false;
 begin insert into public.messages(couple_id,sender_id,body) values(cid,a,'Late write');exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'FAIL: writes continue during deletion';end if;
 blocked:=false;
 begin insert into storage.objects(bucket_id,name) values('couple-media',cid||'/'||a||'/late.jpg');exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'FAIL: uploads continue during deletion';end if;
 reset role;
 if has_function_privilege('authenticated','public.finish_space_delete(uuid)','execute') then raise exception 'FAIL: app can finish privileged deletion';end if;
 set local role service_role;
 if not public.finish_space_delete(cid) then raise exception 'FAIL: empty space could not finish';end if;
 reset role;
 if exists(select 1 from public.couples where id=cid) or exists(select 1 from public.messages where couple_id=cid) or exists(select 1 from public.profiles where couple_id=cid) or exists(select 1 from private.push_outbox where couple_id=cid) then raise exception 'FAIL: rows remain';end if;
 if not exists(select 1 from auth.users where id=a) then raise exception 'FAIL: account removed';end if;
end $test$;
select 'PASS: outsider deletion blocked, idempotent request, writes/uploads frozen, privileged cleanup, cascade and accounts preserved' test_result;
rollback;
