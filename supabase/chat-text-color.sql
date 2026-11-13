-- Optional per-message text colors for global chat.
-- Run once in the Supabase SQL editor.
alter table public.messages add column if not exists text_color text;
alter table public.messages drop constraint if exists messages_text_color_format;
alter table public.messages add constraint messages_text_color_format
  check (text_color is null or text_color ~ '^#[0-9A-Fa-f]{6}$');
notify pgrst, 'reload schema';
