
begin;
do $test$
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); third uuid:=gen_random_uuid();
  cid uuid; msg uuid:=gen_random_uuid(); mem uuid:=gen_random_uuid(); d uuid:=gen_random_uuid();
  x jsonb; t text; n integer;
begin
  insert into auth.users(id,email,aud,role) values
    (a,a::text||'@example.invalid','authenticated','authenticated'),
    (b,b::text||'@example.invalid','authenticated','authenticated'),
    (third,third::text||'@example.invalid','authenticated','authenticated');
  insert into public.couples(owner_id,partner_id) values(a,b) returning id into cid;
  insert into public.profiles(user_id,couple_id) values(a,cid);
  insert into public.messages(id,couple_id,sender_id,body) values(msg,cid,a,'Private chat');
  insert into public.message_states(message_id,couple_id,user_id) values(msg,cid,a);
  insert into public.memories(id,couple_id,author_id,media_path) values(mem,cid,a,cid||'/'||a||'/test.jpg');
  insert into public.reactions(couple_id,user_id,message_id) values(cid,a,msg);
  insert into public.dates(id,couple_id,author_id,title,starts_at) values(d,cid,a,'Date',now()+interval '2 days');
  insert into public.date_responses(date_id,couple_id,user_id,status) values(d,cid,b,'accepted');
  insert into public.anniversaries(couple_id,author_id,title,event_date) values(cid,a,'Anniversary',current_date);
  insert into public.list_items(couple_id,author_id,list_kind,title) values(cid,a,'todo','Private item');
  insert into public.love_notes(couple_id,author_id,body) values(cid,a,'Private note');
  insert into public.journal_entries(couple_id,author_id,body) values(cid,a,'Only mine');
  insert into storage.objects(bucket_id,name) values('couple-media',cid||'/'||a||'/test.jpg');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  x:=public.send_miss_me(cid);
  if x->>'id' is null then raise exception 'FAIL: first miss-me rejected'; end if;
  x:=public.send_miss_me(cid);
  if x->>'error' is distinct from 'cooldown' then raise exception 'FAIL: cooldown bypass'; end if;
  begin
    insert into public.miss_me(couple_id,sender_id) values(cid,a);
    raise exception 'FAIL: cooldown bypass through direct insertion';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  select count(*) into n from public.messages where id=msg;
  if n<>1 then raise exception 'FAIL: partner cannot read chat'; end if;
  select count(*) into n from public.journal_entries where couple_id=cid;
  if n<>0 then raise exception 'FAIL: partner can read private journal'; end if;
  update public.journal_entries set shared=true where couple_id=cid;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'FAIL: partner can expose private journal'; end if;
  update public.list_items set completed=true where couple_id=cid;
  get diagnostics n=row_count;
  if n<>1 then raise exception 'FAIL: partner cannot edit shared list'; end if;
  select count(*) into n from storage.objects where bucket_id='couple-media' and name=cid||'/'||a||'/test.jpg';
  if n<>1 then raise exception 'FAIL: partner cannot access media'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',third,'role','authenticated')::text,true);
  foreach t in array array['profiles','messages','message_states','memories','reactions','dates','date_responses',
    'anniversaries','list_items','love_notes','journal_entries','miss_me'] loop
    execute format('select count(*) from public.%I where couple_id=$1',t) into n using cid;
    if n<>0 then raise exception 'FAIL: outsider read %',t; end if;
  end loop;
  begin
    insert into public.messages(couple_id,sender_id,body) values(cid,third,'Intrusion');
    raise exception 'FAIL: outsider chat write';
  exception when insufficient_privilege then null; end;
  begin
    perform public.send_miss_me(cid);
    raise exception 'FAIL: outsider miss-me';
  exception when insufficient_privilege then null; end;
  select count(*) into n from storage.objects where bucket_id='couple-media' and name=cid||'/'||a||'/test.jpg';
  if n<>0 then raise exception 'FAIL: outsider media read'; end if;
  begin
    insert into storage.objects(bucket_id,name) values('couple-media',cid||'/'||third||'/intrusion.jpg');
    raise exception 'FAIL: outsider media upload';
  exception when insufficient_privilege then null; end;
  reset role;
end $test$;
select 'PASS: partner chat/media access, private journal isolation, shared-list editing, 12 content-table outsider read tests, outsider chat/miss-me/media rejection, atomic miss-me cooldown and direct-insert rejection' as test_result;
rollback;
