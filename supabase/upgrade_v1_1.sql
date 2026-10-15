-- Additive upgrade. Existing couples, chat and signing identity are preserved.
begin;
alter table public.messages add column edited_at timestamptz, add column deleted_at timestamptz, add column pinned boolean not null default false, add column forwarded boolean not null default false, add column file_name text check(length(file_name)<=180), add column mime_type text, add column file_size integer check(file_size between 0 and 5242880);
alter table public.messages drop constraint messages_media_kind_check;
alter table public.messages add constraint messages_media_kind_check check(media_kind in ('photo','voice','file'));
alter table public.message_states add column starred boolean not null default false;
alter table public.reactions add column emoji text not null default '❤️' check(emoji in ('❤️','😂','🥰','👍','😢','🔥'));
alter table public.profiles add column availability text check(length(availability)<=80),add column availability_until timestamptz;
grant update(starred) on public.message_states to authenticated;
grant update(availability,availability_until) on public.profiles to authenticated;
create function private.mutate_message(p_id uuid,p_action text,p_body text default null) returns void language plpgsql security definer set search_path='' as $$
declare m public.messages;begin
 select * into m from public.messages where id=p_id for update;
 if not exists(select 1 from public.couples where id=m.couple_id and deleting_at is null and auth.uid() in(owner_id,partner_id)) then raise exception 'Not allowed' using errcode='42501';end if;
 if p_action in ('pin','unpin') then update public.messages set pinned=(p_action='pin') where id=p_id;return;end if;
 if m.sender_id<>auth.uid() or m.deleted_at is not null then raise exception 'Not allowed' using errcode='42501';end if;
 if p_action='edit' and m.media_path is null and length(trim(p_body)) between 1 and 8000 then update public.messages set body=trim(p_body),edited_at=now() where id=p_id;
 elsif p_action='delete' then update public.messages set body='This message was deleted',media_path=null,media_kind=null,file_name=null,mime_type=null,file_size=null,deleted_at=now(),pinned=false where id=p_id;
 else raise exception 'Invalid action';end if;end $$;
create function public.mutate_message(p_id uuid,p_action text,p_body text default null) returns void language sql security invoker set search_path='' as $$select private.mutate_message(p_id,p_action,p_body)$$;
revoke all on function private.mutate_message(uuid,text,text),public.mutate_message(uuid,text,text) from public,anon;grant execute on function private.mutate_message(uuid,text,text),public.mutate_message(uuid,text,text) to authenticated;
create table public.memory_collections(id uuid primary key default gen_random_uuid(),couple_id uuid not null references public.couples on delete cascade,author_id uuid not null references auth.users,title text not null check(length(title) between 1 and 100),created_at timestamptz not null default now(),unique(couple_id,id));
alter table public.memories add column collection_id uuid,add foreign key(couple_id,collection_id) references public.memory_collections(couple_id,id);
grant update(collection_id) on public.memories to authenticated;
create table public.expenses(id uuid primary key default gen_random_uuid(),couple_id uuid not null references public.couples on delete cascade,author_id uuid not null references auth.users,title text not null check(length(title) between 1 and 140),amount numeric(12,2) not null check(amount>0),currency text not null default 'INR' check(currency in ('INR','USD','EUR','GBP')),settlement boolean not null default false,created_at timestamptz not null default now());
create table public.letters(id uuid primary key default gen_random_uuid(),couple_id uuid not null references public.couples on delete cascade,author_id uuid not null references auth.users,title text not null check(length(title) between 1 and 120),open_when text not null check(length(open_when)<=200),unlock_at timestamptz,created_at timestamptz not null default now(),unique(couple_id,id));
create table public.letter_contents(id uuid primary key references public.letters(id) on delete cascade,couple_id uuid not null references public.couples on delete cascade,body text not null check(length(body) between 1 and 8000));
create table public.polls(id uuid primary key default gen_random_uuid(),couple_id uuid not null references public.couples on delete cascade,author_id uuid not null references auth.users,question text not null check(length(question) between 1 and 300),options jsonb not null check(jsonb_typeof(options)='array' and jsonb_array_length(options) between 2 and 6),created_at timestamptz not null default now(),unique(couple_id,id));
create table public.poll_votes(poll_id uuid not null,user_id uuid not null references auth.users,couple_id uuid not null references public.couples on delete cascade,choice integer not null check(choice between 0 and 5),primary key(poll_id,user_id),foreign key(couple_id,poll_id) references public.polls(couple_id,id) on delete cascade);
create function private.validate_vote() returns trigger language plpgsql set search_path='' as $$begin if new.choice>= (select jsonb_array_length(options) from public.polls where id=new.poll_id) then raise exception 'Invalid choice';end if;return new;end$$;
create trigger validate_vote before insert or update on public.poll_votes for each row execute function private.validate_vote();
-- Only the most recent position exists; no route/history is collected.
create table public.live_locations(user_id uuid primary key references auth.users,couple_id uuid not null references public.couples on delete cascade,latitude double precision not null check(latitude between -90 and 90),longitude double precision not null check(longitude between -180 and 180),accuracy double precision not null check(accuracy between 0 and 100000),expires_at timestamptz not null,updated_at timestamptz not null default now());
create index live_locations_couple on public.live_locations(couple_id);
alter table public.live_locations enable row level security;
revoke all on public.live_locations from anon,authenticated;grant select on public.live_locations to authenticated;
create policy live_member_read on public.live_locations for select to authenticated using(expires_at>now() and exists(select 1 from public.couples where id=couple_id and deleting_at is null and (select auth.uid()) in(owner_id,partner_id)));
create function private.share_location(p_couple uuid,p_lat double precision,p_lng double precision,p_accuracy double precision,p_until timestamptz) returns void language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null or not exists(select 1 from public.couples where id=p_couple and deleting_at is null and partner_id is not null and auth.uid() in(owner_id,partner_id)) then raise exception 'Not allowed' using errcode='42501';end if;
 if p_until<=now() or p_until>now()+interval '8 hours' then raise exception 'Choose a duration up to eight hours';end if;
 insert into public.live_locations values(auth.uid(),p_couple,p_lat,p_lng,p_accuracy,p_until,now()) on conflict(user_id) do update set couple_id=excluded.couple_id,latitude=excluded.latitude,longitude=excluded.longitude,accuracy=excluded.accuracy,expires_at=excluded.expires_at,updated_at=now();end$$;
create function public.share_location(p_couple uuid,p_lat double precision,p_lng double precision,p_accuracy double precision,p_until timestamptz) returns void language sql security invoker set search_path='' as $$select private.share_location(p_couple,p_lat,p_lng,p_accuracy,p_until)$$;
create function private.stop_location() returns void language sql security definer set search_path='' as $$delete from public.live_locations where user_id=auth.uid()$$;
create function public.stop_location() returns void language sql security invoker set search_path='' as $$select private.stop_location()$$;
revoke all on function private.share_location(uuid,double precision,double precision,double precision,timestamptz),public.share_location(uuid,double precision,double precision,double precision,timestamptz),private.stop_location(),public.stop_location() from public,anon;
grant execute on function private.share_location(uuid,double precision,double precision,double precision,timestamptz),public.share_location(uuid,double precision,double precision,double precision,timestamptz),private.stop_location(),public.stop_location() to authenticated;
do $do$ declare t text;begin
 foreach t in array array['memory_collections','expenses','letters','polls','poll_votes'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select,insert,delete on public.%I to authenticated',t);
 execute format('create policy member_read on public.%I for select to authenticated using(exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)))',t);
 execute format('create policy own_insert on public.%I for insert to authenticated with check(%I=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id)))',t,case when t='poll_votes' then 'user_id' else 'author_id' end);
 execute format('create policy own_delete on public.%I for delete to authenticated using(%I=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and (select auth.uid()) in(c.owner_id,c.partner_id)))',t,case when t='poll_votes' then 'user_id' else 'author_id' end);
 execute format('create index %I on public.%I(couple_id)',t||'_couple_idx',t);
 end loop;
 foreach t in array array['memory_collections','expenses','letters','letter_contents','polls','poll_votes','live_locations'] loop
 execute format('create trigger guard_space_writes before insert or update or delete on public.%I for each row execute function private.guard_space_writes()',t);
 execute format('alter publication supabase_realtime add table public.%I',t);
 end loop;end $do$;
grant update(choice) on public.poll_votes to authenticated;
create policy vote_update on public.poll_votes for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and exists(select 1 from public.couples c where c.id=couple_id and (select auth.uid()) in(c.owner_id,c.partner_id)));
alter table public.letter_contents enable row level security;
revoke all on public.letter_contents from anon,authenticated;grant select on public.letter_contents to authenticated;
create policy unlocked_letter_read on public.letter_contents for select to authenticated using(exists(select 1 from public.letters l join public.couples c on c.id=l.couple_id where l.id=letter_contents.id and l.couple_id=letter_contents.couple_id and c.deleting_at is null and (select auth.uid()) in(c.owner_id,c.partner_id) and (l.author_id=(select auth.uid()) or l.unlock_at is null or l.unlock_at<=now())));
create function private.write_letter(p_couple uuid,p_title text,p_when text,p_body text,p_unlock timestamptz default null) returns uuid language plpgsql security definer set search_path='' as $$declare lid uuid;begin
 if not exists(select 1 from public.couples where id=p_couple and deleting_at is null and auth.uid() in(owner_id,partner_id)) then raise exception 'Not allowed' using errcode='42501';end if;
 insert into public.letters(couple_id,author_id,title,open_when,unlock_at)values(p_couple,auth.uid(),p_title,p_when,p_unlock)returning id into lid;
 insert into public.letter_contents values(lid,p_couple,p_body);return lid;end$$;
create function public.write_letter(p_couple uuid,p_title text,p_when text,p_body text,p_unlock timestamptz default null) returns uuid language sql security invoker set search_path='' as $$select private.write_letter(p_couple,p_title,p_when,p_body,p_unlock)$$;
revoke all on function private.write_letter(uuid,text,text,text,timestamptz),public.write_letter(uuid,text,text,text,timestamptz) from public,anon;grant execute on function private.write_letter(uuid,text,text,text,timestamptz),public.write_letter(uuid,text,text,text,timestamptz) to authenticated;
-- Metadata can only be created with its body, through the transaction above.
revoke insert on public.letters from authenticated;
select cron.schedule('us-expire-locations','*/5 * * * *',$$delete from public.live_locations where expires_at<=now()$$);
update storage.buckets set allowed_mime_types=array['image/jpeg','audio/mp4','audio/x-m4a','application/pdf','text/plain','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'] where id='couple-media';
commit;
