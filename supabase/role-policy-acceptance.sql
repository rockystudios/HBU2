-- HBU Staff Abuse & Consequences Policy acceptance.
-- Run once in the Supabase SQL Editor. Safe to run more than once.
-- Only the send-message Edge Function service role should read or write this table.

create table if not exists public.role_policy_acceptances (
  username text primary key,
  role_name text not null,
  policy_version text not null,
  accepted_at timestamptz not null default now()
);

alter table public.role_policy_acceptances enable row level security;
revoke all on public.role_policy_acceptances from anon, authenticated;
grant all on public.role_policy_acceptances to service_role;

create index if not exists role_policy_acceptances_version_idx
  on public.role_policy_acceptances (policy_version, role_name);

notify pgrst, 'reload schema';
