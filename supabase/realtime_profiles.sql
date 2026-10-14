create policy us_private_realtime_read on realtime.messages for select to authenticated using (
 extension in ('presence','broadcast') and exists(select 1 from public.couples c
 where (select auth.uid()) in(c.owner_id,c.partner_id) and (select realtime.topic()) in
 ('couple:'||c.id||':user:'||c.owner_id,'couple:'||c.id||':user:'||c.partner_id)));
create policy us_private_realtime_write on realtime.messages for insert to authenticated with check (
 extension in ('presence','broadcast') and exists(select 1 from public.couples c
 where (select auth.uid()) in(c.owner_id,c.partner_id)
 and (select realtime.topic())='couple:'||c.id||':user:'||(select auth.uid())));
do $$ declare t text;begin
 foreach t in array array['couples','profiles','messages','message_states','memories','reactions','dates','date_responses','anniversaries','list_items','love_notes','journal_entries','miss_me'] loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
   execute format('alter publication supabase_realtime add table public.%I',t);
  end if;
 end loop;
end $$;
create function private.create_profiles() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(user_id,couple_id) values(new.owner_id,new.id) on conflict(user_id) do nothing;
 if new.partner_id is not null then insert into public.profiles(user_id,couple_id) values(new.partner_id,new.id) on conflict(user_id) do nothing;end if;
 return new;
end $$;
revoke all on function private.create_profiles() from public,anon,authenticated,service_role;
create trigger create_member_profiles after insert or update of partner_id on public.couples for each row execute function private.create_profiles();
