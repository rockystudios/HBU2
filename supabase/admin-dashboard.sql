-- Private audit trail for the centralized admin dashboard.
-- Run once in the Supabase SQL Editor. The Edge Function uses the service role
-- only after revalidating the user's account password and ADMIN_USERNAMES role.
create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  actor text not null,
  action text not null,
  target text,
  details jsonb not null default '{}'::jsonb
);
create index if not exists admin_audit_log_created_at_idx on public.admin_audit_log (created_at desc);
alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from anon, authenticated;
notify pgrst, 'reload schema';
