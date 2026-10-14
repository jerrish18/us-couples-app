create or replace function private.enqueue_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare c public.couples; who uuid; recipient uuid; kind text; payload jsonb; eid uuid;
begin
 select * into c from public.couples where id=new.couple_id;
 if c.partner_id is null then return new; end if;
 who:=case when tg_table_name in ('messages','miss_me') then (to_jsonb(new)->>'sender_id')::uuid
   when tg_table_name='date_responses' then (to_jsonb(new)->>'user_id')::uuid else (to_jsonb(new)->>'author_id')::uuid end;
 recipient:=case when who=c.owner_id then c.partner_id else c.owner_id end;
 kind:=case tg_table_name when 'messages' then 'message' when 'miss_me' then 'miss_me'
   when 'dates' then 'date_invite' else 'date_response' end;
 eid:=case when tg_table_name='date_responses' then (to_jsonb(new)->>'date_id')::uuid else (to_jsonb(new)->>'id')::uuid end;
 payload:=jsonb_build_object('title',case kind when 'miss_me' then 'Your person misses you ❤️'
   when 'message' then 'A message from your person' when 'date_invite' then 'A date, just for us'
   else 'Your person replied to your date' end,
   'body',case kind when 'miss_me' then 'Tap to send some love back.'
   when 'message' then 'Open Us to read it.' else 'Open Us to see the details.' end,
   'route',case when kind='message' then '/chat' when kind='miss_me' then '/' else '/calendar' end,
   'entity_id',eid::text,'kind',kind);
 insert into private.push_outbox(couple_id,recipient_id,kind,payload) values(c.id,recipient,kind,payload);
 perform private.kick_push();
 return new;
end $$;
