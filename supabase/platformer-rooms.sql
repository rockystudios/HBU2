-- Online multiplayer rooms for the platformer.
-- Room membership is enforced by the Edge Function using hashed, per-seat tokens.
-- Browser clients must never access this table directly.
create table if not exists public.platformer_rooms (
  room_code text primary key check (room_code ~ '^[A-Z0-9]{6}$'),
  is_public boolean not null default false,
  level_name text not null,
  level_data jsonb not null,
  status text not null default 'waiting' check (status in ('waiting','playing','closed')),
  host_token_hash text not null,
  guest_token_hash text,
  host_state jsonb not null default '{}'::jsonb,
  guest_state jsonb not null default '{}'::jsonb,
  host_seen_at timestamptz not null default now(),
  guest_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '2 hours')
);

alter table public.platformer_rooms enable row level security;
revoke all on table public.platformer_rooms from anon, authenticated;
grant all on table public.platformer_rooms to service_role;
