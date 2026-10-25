-- Preserve existing bridge users; newer clients explicitly select phone hosting.
alter table public.echo_preferences add column host text not null default 'bridge' check(host in('bridge','phone'));
alter table public.echo_sessions add column host text not null default 'bridge' check(host in('bridge','phone'));
grant update(host) on public.echo_sessions to authenticated;
create function public.echo_claim_answer(p_call uuid,p_answer text,p_host text) returns boolean
language plpgsql security invoker set search_path='' as $$
declare c public.calls;begin
 if p_host not in('bridge','phone') then return false;end if;
 select * into c from public.calls where id=p_call for update;
 if c.id is null or c.callee_id is distinct from auth.uid() or c.state<>'ringing' or c.expires_at<=now() then return false;end if;
 if not exists(select 1 from public.echo_preferences p where p.couple_id=c.couple_id and p.user_id=auth.uid() and p.enabled and p.host=p_host) then return false;end if;
 insert into public.echo_sessions(call_id,callee_id,host) values(c.id,c.callee_id,p_host);
 update public.calls set answer=p_answer,state='connecting' where id=c.id;
 return true;
end $$;
revoke all on function public.echo_claim_answer(uuid,text,text) from public,anon,authenticated;
grant execute on function public.echo_claim_answer(uuid,text,text) to authenticated;
create or replace function public.echo_answer(p_call uuid,p_answer text) returns boolean
language sql security invoker set search_path='' as $$select public.echo_claim_answer(p_call,p_answer,'bridge')$$;
create function public.echo_answer_phone(p_call uuid,p_answer text) returns boolean
language sql security invoker set search_path='' as $$select public.echo_claim_answer(p_call,p_answer,'phone')$$;
revoke all on function public.echo_answer_phone(uuid,text) from public,anon,authenticated;
grant execute on function public.echo_answer_phone(uuid,text) to authenticated;
