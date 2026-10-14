
create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  couple_id uuid not null references public.couples(id) on delete cascade,
  display_name text not null default 'Your person' check(char_length(display_name) between 1 and 60),
  nickname text check(char_length(nickname)<=60),
  avatar_path text,
  timezone text not null default 'Asia/Kolkata',
  city text not null default 'Chennai',
  mood text check(char_length(mood)<=40),
  mood_date date,
  last_seen timestamptz,
  updated_at timestamptz not null default now()
);
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  body text check(char_length(body)<=8000),
  media_path text,
  media_kind text check(media_kind in ('photo','voice')),
  reply_to uuid,
  created_at timestamptz not null default now(),
  unique(couple_id,id),
  foreign key(couple_id,reply_to) references public.messages(couple_id,id),
  check(coalesce(length(body),0)>0 or media_path is not null),
  check((media_path is null)=(media_kind is null))
);
create index messages_timeline_idx on public.messages(couple_id,created_at,id);
create table public.message_states (
  message_id uuid not null,
  couple_id uuid not null,
  user_id uuid not null references auth.users(id),
  read_at timestamptz,
  hidden boolean not null default false,
  primary key(message_id,user_id),
  foreign key(couple_id,message_id) references public.messages(couple_id,id) on delete cascade
);
create table public.memories (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null references auth.users(id),
  media_path text not null,
  caption text not null default '' check(char_length(caption)<=4000),
  memory_date date not null default current_date,
  created_at timestamptz not null default now(),
  unique(couple_id,id)
);
create table public.reactions (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  message_id uuid,
  memory_id uuid,
  foreign key(couple_id,message_id) references public.messages(couple_id,id) on delete cascade,
  foreign key(couple_id,memory_id) references public.memories(couple_id,id) on delete cascade,
  check ((message_id is null)<>(memory_id is null)),
  unique(user_id,message_id),
  unique(user_id,memory_id)
);
create table public.dates (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null references auth.users(id),
  title text not null check(char_length(title) between 1 and 120),
  starts_at timestamptz not null,
  place text not null default '' check(char_length(place)<=250),
  notes text not null default '' check(char_length(notes)<=4000),
  created_at timestamptz not null default now(),
  unique(couple_id,id)
);
create table public.date_responses (
  date_id uuid not null,
  couple_id uuid not null,
  user_id uuid not null references auth.users(id),
  status text not null check(status in ('accepted','suggested','declined')),
  proposed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(date_id,user_id),
  foreign key(couple_id,date_id) references public.dates(couple_id,id) on delete cascade,
  check((status='suggested')=(proposed_at is not null))
);
create table public.anniversaries (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null references auth.users(id),
  title text not null check(char_length(title) between 1 and 120),
  event_date date not null,
  yearly boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.list_items (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null references auth.users(id),
  list_kind text not null check(list_kind in ('bucket','todo','grocery')),
  title text not null check(char_length(title) between 1 and 500),
  completed boolean not null default false,
  updated_at timestamptz not null default now()
);
create table public.love_notes (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null references auth.users(id),
  body text not null check(char_length(body) between 1 and 2000),
  note_date date not null default current_date,
  created_at timestamptz not null default now(),
  unique(couple_id,author_id,note_date)
);
create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null references auth.users(id),
  body text not null check(char_length(body) between 1 and 20000),
  shared boolean not null default false,
  entry_date date not null default current_date,
  updated_at timestamptz not null default now()
);
create table public.miss_me (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index miss_me_cooldown_idx on public.miss_me(couple_id,sender_id,created_at desc);
create table public.device_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now()
);
create table public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  messages boolean not null default true,
  miss_me boolean not null default true,
  dates boolean not null default true,
  reminders boolean not null default true,
  nudges boolean not null default false,
  quiet_start time,
  quiet_end time,
  timezone text not null default 'Asia/Kolkata',
  check ((quiet_start is null)=(quiet_end is null))
);

-- Explicit grants: clients cannot change row identifiers, membership, or authors.
do $$
declare t text; author_col text;
begin
  foreach t in array array['profiles','messages','message_states','memories','reactions','dates',
    'date_responses','anniversaries','list_items','love_notes','journal_entries','miss_me'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public, anon, authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
    execute format('create policy member_read on public.%I for select to authenticated using
      (exists(select 1 from public.couples c where c.id=couple_id and (select auth.uid()) in (c.owner_id,c.partner_id)))',t);
    if t <> 'miss_me' then
      author_col:=case when t='messages' then 'sender_id'
        when t in ('profiles','message_states','reactions','date_responses') then 'user_id' else 'author_id' end;
      execute format('grant insert on public.%I to authenticated',t);
      execute format('create policy own_insert on public.%I for insert to authenticated with check
        (%I=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and
        (select auth.uid()) in (c.owner_id,c.partner_id)))',t,author_col);
    end if;
    execute format('create index %I on public.%I(couple_id)', t||'_couple_idx',t);
  end loop;
end $$;
-- Private journals require additional author/share restriction.
drop policy member_read on public.journal_entries;
create policy journal_read on public.journal_entries for select to authenticated
using ((author_id=(select auth.uid()) or shared) and exists(
  select 1 from public.couples c where c.id=couple_id and (select auth.uid()) in(c.owner_id,c.partner_id)));
-- Hidden state is visible to its owner, receipts to the partner; boolean only, no private text.
grant update(read_at,hidden) on public.message_states to authenticated;
grant update(display_name,nickname,avatar_path,timezone,city,mood,mood_date,last_seen,updated_at) on public.profiles to authenticated;
grant update(status,proposed_at,updated_at) on public.date_responses to authenticated;
grant update(body,shared,entry_date,updated_at) on public.journal_entries to authenticated;
grant update(body,note_date) on public.love_notes to authenticated;
grant update(caption,memory_date) on public.memories to authenticated;
grant update(title,starts_at,place,notes) on public.dates to authenticated;
grant update(title,event_date,yearly) on public.anniversaries to authenticated;
grant update(title,completed,updated_at) on public.list_items to authenticated;
do $$
declare t text; col text;
begin
  foreach t in array array['profiles','message_states','date_responses','journal_entries','love_notes','memories','dates','anniversaries','list_items'] loop
    col:=case when t in('profiles','message_states','date_responses') then 'user_id' else 'author_id' end;
    execute format('create policy own_update on public.%I for update to authenticated using
      ((%I=(select auth.uid()) or %L=''list_items'') and exists(select 1 from public.couples c where
       c.id=couple_id and (select auth.uid()) in(c.owner_id,c.partner_id)))
      with check ((%I=(select auth.uid()) or %L=''list_items'') and exists(select 1 from public.couples c where
       c.id=couple_id and (select auth.uid()) in(c.owner_id,c.partner_id)))',t,col,t,col,t);
  end loop;
  foreach t in array array['memories','reactions','dates','anniversaries','list_items','love_notes','journal_entries'] loop
    col:=case when t='reactions' then 'user_id' else 'author_id' end;
    execute format('grant delete on public.%I to authenticated',t);
    execute format('create policy own_delete on public.%I for delete to authenticated using
      ((%I=(select auth.uid()) or %L=''list_items'') and exists(select 1 from public.couples c where
       c.id=couple_id and (select auth.uid()) in(c.owner_id,c.partner_id)))',t,col,t);
  end loop;
  foreach t in array array['device_tokens','notification_preferences'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select,insert,delete on public.%I to authenticated',t);
    execute format('create policy own_data on public.%I for all to authenticated using
      (user_id=(select auth.uid())) with check(user_id=(select auth.uid()))',t);
  end loop;
end $$;
grant update(updated_at) on public.device_tokens to authenticated;
grant update(messages,miss_me,dates,reminders,nudges,quiet_start,quiet_end,timezone) on public.notification_preferences to authenticated;

create function private.send_miss_me(p_couple uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); c public.couples; previous timestamptz; event_id uuid;
begin
  if uid is null then raise exception 'Sign in first' using errcode='42501'; end if;
  select * into c from public.couples where id=p_couple for update;
  if c.id is null or uid not in(c.owner_id,coalesce(c.partner_id,c.owner_id)) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if c.partner_id is null then return jsonb_build_object('error','partner_required'); end if;
  select max(created_at) into previous from public.miss_me where couple_id=p_couple and sender_id=uid;
  if previous>now()-interval '5 minutes' then
    return jsonb_build_object('error','cooldown','retry_at',previous+interval '5 minutes');
  end if;
  insert into public.miss_me(couple_id,sender_id) values(p_couple,uid) returning id into event_id;
  return jsonb_build_object('id',event_id);
end $$;
revoke all on function private.send_miss_me(uuid) from public,anon;
grant execute on function private.send_miss_me(uuid) to authenticated;
create function public.send_miss_me(p_couple uuid)
returns jsonb language sql security invoker set search_path=''
as $$ select private.send_miss_me(p_couple); $$;
revoke all on function public.send_miss_me(uuid) from public,anon;
grant execute on function public.send_miss_me(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('couple-media','couple-media',false,5242880,array['image/jpeg','image/png','image/webp','audio/mp4','audio/mpeg','audio/aac','audio/ogg']);
create policy couple_media_read on storage.objects for select to authenticated using
(bucket_id='couple-media' and exists(select 1 from public.couples c
  where c.id::text=(storage.foldername(name))[1] and (select auth.uid()) in(c.owner_id,c.partner_id)));
create policy couple_media_upload on storage.objects for insert to authenticated with check
(bucket_id='couple-media' and (storage.foldername(name))[2]=(select auth.uid())::text and
 exists(select 1 from public.couples c where c.id::text=(storage.foldername(name))[1]
 and (select auth.uid()) in(c.owner_id,c.partner_id)));
create policy couple_media_delete on storage.objects for delete to authenticated using
(bucket_id='couple-media' and exists(select 1 from public.couples c
 where c.id::text=(storage.foldername(name))[1] and (select auth.uid()) in(c.owner_id,c.partner_id)));
