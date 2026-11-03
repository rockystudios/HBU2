-- Run once in the Supabase SQL editor, then redeploy the send-message function.
-- Adds the settings table used by the /lock, /unlock and /slowmode commands.

create table if not exists public.chat_settings (
  key text primary key,
  value text not null
);
alter table public.chat_settings enable row level security;
revoke all on public.chat_settings from anon, authenticated;

notify pgrst, 'reload schema';
