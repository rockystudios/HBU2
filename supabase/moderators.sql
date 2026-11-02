-- Run once in the Supabase SQL editor, then redeploy the send-message function.
-- Lets the admin (Rocky) appoint moderators who can delete main-chat messages
-- and ban users.

alter table public.accounts add column if not exists is_mod boolean not null default false;

-- The browser never reads accounts directly (all access is revoked), so is_mod
-- can only be changed through the send-message function by the admin.
notify pgrst, 'reload schema';

-- Handy admin commands:
--   List mods:   select username from accounts where is_mod;
--   Add a mod:   update accounts set is_mod = true  where lower(username) = 'someone';
--   Remove a mod: update accounts set is_mod = false where lower(username) = 'someone';
