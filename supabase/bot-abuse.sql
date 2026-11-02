-- Run once in the Supabase SQL editor, then redeploy the send-message function.
-- Lets moderators block a user from talking to mod-bot. mod-bot also blocks
-- people automatically after 3 spam attempts until a moderator restores them.

alter table public.accounts add column if not exists bot_banned boolean not null default false;
alter table public.accounts add column if not exists bot_strikes integer not null default 0;

notify pgrst, 'reload schema';

-- Handy admin commands:
--   List blocked:  select username from accounts where bot_banned;
--   Restore:       update accounts set bot_banned = false, bot_strikes = 0 where lower(username) = 'someone';
