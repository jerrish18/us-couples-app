
begin;
do $test$
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  created jsonb; joined jsonb; cid uuid; code text; n integer;
begin
  insert into auth.users(id,email,aud,role) values
    (a,a::text||'@example.invalid','authenticated','authenticated'),
    (b,b::text||'@example.invalid','authenticated','authenticated'),
    (outsider,outsider::text||'@example.invalid','authenticated','authenticated');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  created := public.create_couple('Security test',date '2024-05-27');
  cid := (created->>'couple_id')::uuid; code:=created->>'invite_code';
  if length(code)<>6 then raise exception 'FAIL: invite must have six characters'; end if;
  if public.get_invite() is distinct from code then raise exception 'FAIL: owner cannot recover invite'; end if;
  begin
    perform public.create_couple('Duplicate',null);
    raise exception 'FAIL: second space accepted';
  exception when unique_violation then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  joined:=public.join_couple(code);
  if (joined->>'couple_id')::uuid is distinct from cid then raise exception 'FAIL: partner cannot join'; end if;
  select count(*) into n from public.couples where id=cid and partner_id=b;
  if n<>1 then raise exception 'FAIL: partner cannot read'; end if;
  begin
    update public.couples set partner_id=null where id=cid;
    raise exception 'FAIL: partner slot can be cleared';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
  joined:=public.join_couple(code);
  if joined->>'error' is distinct from 'invalid_or_locked' then raise exception 'FAIL: third user accepted'; end if;
  select count(*) into n from public.couples where id=cid;
  if n<>0 then raise exception 'FAIL: third user can read couple'; end if;
  update public.couples set name='Intrusion' where id=cid;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'FAIL: third user can edit couple'; end if;
  begin
    insert into public.couples(owner_id,partner_id,name) values(outsider,a,'Forgery');
    raise exception 'FAIL: membership can be forged';
  exception when insufficient_privilege then null; end;
  begin
    perform * from private.invites;
    raise exception 'FAIL: private invitation exposed';
  exception when insufficient_privilege then null; end;
  for n in 1..5 loop joined:=public.join_couple('ZZZZZZ'); end loop;
  if joined->>'error' is distinct from 'try_later' then raise exception 'FAIL: invite guessing is not limited'; end if;
  reset role;
  if exists(select 1 from private.invites where couple_id=cid) then raise exception 'FAIL: used invitation not consumed'; end if;
end $test$;
select 'PASS: six-character invite, owner invite retrieval, duplicate space rejection, partner join/read, immutable partner slot, third-user join/read/write lockout, direct forgery blocked, private invites hidden, guess rate limit, consumed invitation' as test_result;
rollback;
