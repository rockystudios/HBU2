-- Run after deploying send-message with ALTCHA signup verification.
-- Set ALTCHA_HMAC_SECRET in the Edge Function secrets before enabling signup.
create table if not exists public.hbu_altcha_used_challenges (
  signature text primary key,
  expires_at timestamptz not null
);

alter table public.hbu_altcha_used_challenges enable row level security;
revoke all on public.hbu_altcha_used_challenges from public, anon, authenticated;
grant select, insert, delete on public.hbu_altcha_used_challenges to service_role;

-- Route account creation through send-message so it can verify ALTCHA.
revoke execute on function public.hbu_signup(text, text, text) from anon, authenticated, public;
grant execute on function public.hbu_signup(text, text, text) to service_role;
