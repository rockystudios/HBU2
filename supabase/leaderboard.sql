-- HBU leaderboard. Run once in the Supabase SQL editor (after coins.sql).
create or replace function public.hbu_leaderboard()
returns table (username text, coins integer, avatar text) language sql security definer set search_path = public as $$
  select a.username, a.coins, a.avatar from accounts a order by a.coins desc, a.username limit 20;
$$;
grant execute on function public.hbu_leaderboard() to anon, authenticated;
