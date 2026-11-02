-- Inbox summary for notifications and "most recent chat first" ordering.
-- Run once in the Supabase SQL editor. No Edge Function change is needed.

create or replace function public.hbu_inbox(p_username text, p_password text)
returns table (partner text, last_at timestamptz, last_user text, last_message text)
language plpgsql security definer set search_path = public, extensions as $$
declare me text;
begin
  select username into me from accounts
   where lower(username) = lower(p_username) and password = crypt(p_password, password);
  if me is null then raise exception 'Wrong username or password'; end if;
  return query
    select distinct on (p)
           p, m.created_at, m."user", m.message
      from (
        select case when m2."user" = me then m2.receiver else m2."user" end as p, m2.id
          from messages m2
         where m2.receiver <> 'everyone' and (m2."user" = me or m2.receiver = me)
      ) x
      join messages m on m.id = x.id
     order by p, m.created_at desc;
end;
$$;

grant execute on function public.hbu_inbox(text, text) to anon, authenticated;

notify pgrst, 'reload schema';
