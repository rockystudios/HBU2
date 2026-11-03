-- Run once in the Supabase SQL editor. No Edge Function change is needed.
-- Lets the chat show a check mark next to moderators' names.

create or replace function public.hbu_mod_names()
returns table (username text)
language sql security definer set search_path = public as $$
  select a.username from accounts a where a.is_mod = true;
$$;

grant execute on function public.hbu_mod_names() to anon, authenticated;

notify pgrst, 'reload schema';
