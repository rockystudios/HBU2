-- Deleted messages are hidden, not erased. Run once in the Supabase SQL editor. Safe to run again.
-- Redeploy the send-message Edge Function afterwards (Verify JWT off).
alter table public.messages add column if not exists deleted_at timestamptz;
alter table public.messages add column if not exists deleted_by text;

-- Hidden messages disappear for everyone reading the main chat.
drop policy if exists "read main chat" on public.messages;
create policy "read main chat" on public.messages for select using (receiver = 'everyone' and deleted_at is null);

create index if not exists messages_deleted_idx on public.messages (deleted_at desc) where deleted_at is not null;
notify pgrst, 'reload schema';
