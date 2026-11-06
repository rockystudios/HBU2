-- Run before deploying send-message with image signup verification.
create table if not exists public.hbu_image_challenges (
  id uuid primary key,
  answer_signature text not null,
  expires_at timestamptz not null
);

alter table public.hbu_image_challenges enable row level security;
revoke all on public.hbu_image_challenges from public, anon, authenticated;
grant select, insert, delete on public.hbu_image_challenges to service_role;

-- Account creation must remain behind the Edge Function.
revoke execute on function public.hbu_signup(text, text, text) from public, anon, authenticated;
grant execute on function public.hbu_signup(text, text, text) to service_role;
