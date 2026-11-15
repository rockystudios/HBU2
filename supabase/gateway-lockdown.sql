-- HBU2 gateway lockdown
-- Installs a database-side gate for Supabase Data API (PostgREST).
-- Only the Cloudflare Worker should possess the raw HBU_GATEWAY_TOKEN.
-- The send-message Edge Function checks that same secret independently.
-- This script stores only the SHA-256 hash, never the raw token.
--
-- Before running: set HBU_GATEWAY_TOKEN as a SECRET in both:
--   1) Cloudflare Worker "hbu2" > Settings > Variables and Secrets
--   2) Supabase > Edge Functions > Secrets
-- Use the exact same 64-character hex value in both locations.

create schema if not exists private;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists private.hbu_gateway_config (
  singleton boolean primary key default true check (singleton),
  token_sha256 text not null check (token_sha256 ~ '^[0-9a-f]{64}$'),
  updated_at timestamptz not null default now()
);

revoke all on schema private from public, anon, authenticated;
revoke all on private.hbu_gateway_config from public, anon, authenticated, service_role;

insert into private.hbu_gateway_config (singleton, token_sha256)
values (true, 'f929ff8ed63a5766d41b93eb7960955c37005097ce946447bec05f693d3f93c6')
on conflict (singleton) do update
set token_sha256 = excluded.token_sha256,
    updated_at = now();

create or replace function public.hbu_require_gateway_token()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  claims jsonb;
  request_role text;
  request_headers jsonb;
  supplied_token text;
  expected_hash text;
begin
  claims := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );

  request_role := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    claims ->> 'role',
    ''
  );

  -- Trusted Edge Functions use the service_role key and are server-side.
  if request_role = 'service_role' then
    return;
  end if;

  request_headers := coalesce(
    nullif(current_setting('request.headers', true), '')::jsonb,
    '{}'::jsonb
  );
  supplied_token := request_headers ->> 'x-hbu-gateway-token';

  select token_sha256
    into expected_hash
    from private.hbu_gateway_config
   where singleton = true;

  if supplied_token is null
     or length(supplied_token) <> 64
     or expected_hash is null
     or encode(digest(convert_to(supplied_token, 'UTF8'), 'sha256'), 'hex') <> expected_hash
  then
    raise sqlstate 'PGRST'
      using
        message = json_build_object(
          'code', 'HBU_GATEWAY_REQUIRED',
          'message', 'HBU2 gateway authorization required',
          'details', null,
          'hint', null
        )::text,
        detail = json_build_object(
          'status', 403,
          'status_text', 'Forbidden',
          'headers', '{}'::json
        )::text;
  end if;
end;
$$;

revoke all on function public.hbu_require_gateway_token() from public;
grant execute on function public.hbu_require_gateway_token() to anon, authenticated, service_role;

alter role authenticator
  set pgrst.db_pre_request = 'public.hbu_require_gateway_token';

notify pgrst, 'reload config';

-- Verification after install:
-- SELECT current_setting('pgrst.db_pre_request', true);
-- Direct REST requests without the token should return HTTP 403.
-- Requests through https://hbu2.schooogle.workers.dev should continue working.
