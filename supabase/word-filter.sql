-- Run once in the Supabase SQL editor, then redeploy the send-message function.
-- Chat messages are no longer checked by AI. Instead, any word or phrase in this
-- table is replaced with *** (moderators add, edit and delete them in the chat's
-- admin panel).

create table if not exists public.banned_words (
  id bigint generated always as identity primary key,
  word text not null,
  created_by text,
  created_at timestamptz not null default now()
);
create unique index if not exists banned_words_word_key on public.banned_words (lower(word));

alter table public.banned_words enable row level security;
revoke all on public.banned_words from anon, authenticated;

-- A few starters. Edit or delete them from the admin panel.
insert into public.banned_words (word, created_by) values
  ('fuck', 'setup'), ('shit', 'setup'), ('bitch', 'setup'), ('asshole', 'setup'),
  ('dick', 'setup'), ('pussy', 'setup'), ('porn', 'setup'), ('cock', 'setup')
on conflict do nothing;

notify pgrst, 'reload schema';
