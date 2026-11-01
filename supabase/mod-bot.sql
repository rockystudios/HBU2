-- Run once in the Supabase SQL editor, after accounts-and-dms.sql.
-- Adds chat bans and a moderation log, and forces all sending through the
-- send-message Edge Function (mod-bot) by locking the old hbu_send function.

alter table public.accounts add column if not exists banned_until timestamptz;
alter table public.accounts add column if not exists ban_reason text;

create table if not exists public.mod_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  username text,
  receiver text,
  original text,
  edited text,
  action text,
  reason text
);
alter table public.mod_log enable row level security;
revoke all on public.mod_log from anon, authenticated;

revoke execute on function public.hbu_send(text, text, text, text) from public, anon, authenticated;
grant execute on function public.hbu_send(text, text, text, text) to service_role;

notify pgrst, 'reload schema';

-- Handy admin commands:
--   Unban:      update accounts set banned_until = null, ban_reason = null where username = 'someone';
--   Ban 1 week: update accounts set banned_until = now() + interval '7 days', ban_reason = 'reason' where username = 'someone';
--   Review:     select * from mod_log order by created_at desc limit 50;
