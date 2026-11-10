-- HBU2 SECURITY HARDENING (migration 1)
-- Run this file ONCE in Supabase Dashboard -> SQL Editor before deploying
-- the updated send-message Edge Function.
-- Limits are isolated per account + action. One user cannot consume another
-- user's quota. IP limits for Edge Function actions are stored separately.

create table if not exists public.hbu_edge_rate_buckets (
  subject text not null,
  action text not null,
  window_start bigint not null,
  hits integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (subject, action, window_start)
);

create table if not exists public.hbu_write_events (
  id bigint generated always as identity primary key,
  actor text not null,
  action text not null,
  created_at timestamptz not null default now()
);
create index if not exists hbu_write_events_actor_action_time_idx
  on public.hbu_write_events (lower(actor), action, created_at desc);

alter table public.hbu_edge_rate_buckets enable row level security;
alter table public.hbu_write_events enable row level security;
revoke all on public.hbu_edge_rate_buckets, public.hbu_write_events from public, anon, authenticated;
grant select, insert, update, delete on public.hbu_edge_rate_buckets to service_role;
grant select, insert on public.hbu_write_events to service_role;
grant usage, select on sequence public.hbu_write_events_id_seq to service_role;

-- Atomic fixed-window limiter for trusted Edge Function calls. Returns false
-- instead of raising, so rejected attempts are committed and counted.
create or replace function public.hbu_edge_rate_limit(
  p_subject text,
  p_action text,
  p_limit integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  bucket bigint;
  current_hits integer;
  clean_subject text := left(coalesce(nullif(trim(p_subject), ''), 'unknown'), 160);
  clean_action text := left(coalesce(nullif(trim(p_action), ''), 'unknown'), 80);
  max_hits integer := greatest(1, least(coalesce(p_limit, 1), 10000));
  window_size integer := greatest(1, least(coalesce(p_window_seconds, 60), 86400));
begin
  bucket := floor(extract(epoch from clock_timestamp()) / window_size)::bigint * window_size;
  delete from public.hbu_edge_rate_buckets
   where subject = clean_subject and action = clean_action
     and window_start < bucket - (window_size * 2);
  perform pg_advisory_xact_lock(hashtextextended(clean_subject || ':' || clean_action || ':' || bucket::text, 0));
  insert into public.hbu_edge_rate_buckets as existing(subject, action, window_start, hits, updated_at)
  values (clean_subject, clean_action, bucket, 1, now())
  on conflict (subject, action, window_start)
  do update set hits = least(existing.hits + 1, max_hits + 1), updated_at = now()
  returning hits into current_hits;
  return current_hits <= max_hits;
end;
$$;
revoke all on function public.hbu_edge_rate_limit(text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.hbu_edge_rate_limit(text, text, integer, integer) to service_role;

-- Trigger-based limits apply even when a copied client calls PostgREST directly
-- instead of going through the Edge Function. Successful writes are recorded.
create or replace function public.hbu_guard_write_rate()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_name text;
  action_name text := tg_argv[1];
  max_hits integer := tg_argv[2]::integer;
  window_seconds integer := tg_argv[3]::integer;
  recent_hits integer;
begin
  actor_name := lower(trim(coalesce(to_jsonb(new)->>tg_argv[0], '')));
  if actor_name = '' then
    raise exception 'A valid account is required for this action.' using errcode = '22023';
  end if;
  -- Serialize concurrent requests for the same user/action before counting.
  perform pg_advisory_xact_lock(hashtextextended(actor_name || ':' || action_name, 0));
  if tg_when = 'BEFORE' then
    select count(*)::integer into recent_hits
      from public.hbu_write_events
     where lower(actor) = actor_name
       and action = action_name
       and created_at > now() - make_interval(secs => window_seconds);
    if recent_hits >= max_hits then
      raise exception 'You are doing this too quickly. Please wait a little and try again.'
        using errcode = 'P0001', detail = 'HBU_RATE_LIMIT';
    end if;
    return new;
  end if;
  insert into public.hbu_write_events(actor, action) values (actor_name, action_name);
  return new;
end;
$$;
revoke all on function public.hbu_guard_write_rate() from public, anon, authenticated;

-- Account coin debits (bets, purchases, transfers) are limited separately.
-- Incoming transfers do not consume the recipient's quota.
create or replace function public.hbu_guard_coin_debit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_name text := lower(trim(coalesce(new.username, '')));
  recent_hits integer;
begin
  if old.coins is null or new.coins is null or new.coins >= old.coins then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(actor_name || ':coin_debit', 0));
  if tg_when = 'BEFORE' then
    select count(*)::integer into recent_hits
      from public.hbu_write_events
     where lower(actor) = actor_name
       and action = 'coin_debit'
       and created_at > now() - interval '1 minute';
    if recent_hits >= 30 then
      raise exception 'Too many coin transactions. Please wait a minute and try again.'
        using errcode = 'P0001', detail = 'HBU_RATE_LIMIT';
    end if;
    return new;
  end if;
  insert into public.hbu_write_events(actor, action) values (actor_name, 'coin_debit');
  return new;
end;
$$;
revoke all on function public.hbu_guard_coin_debit() from public, anon, authenticated;

-- Remove prior copies so this migration is safe to rerun.
do $$
declare item record;
begin
  for item in select * from (values
    ('accounts', 'username', 'signup', 3, 3600, 'INSERT'),
    ('messages', 'user', 'chat_message', 10, 30, 'INSERT'),
    ('social_posts', 'author', 'social_post', 3, 600, 'INSERT'),
    ('social_likes', 'username', 'social_like', 40, 60, 'INSERT'),
    ('social_follows', 'follower', 'social_follow', 20, 600, 'INSERT'),
    ('poll_votes', 'username', 'poll_vote', 12, 60, 'INSERT OR UPDATE'),
    ('shared_links', 'posted_by', 'shared_link', 5, 3600, 'INSERT'),
    ('user_apps', 'owner', 'app_save', 12, 60, 'INSERT OR UPDATE'),
    ('app_installs', 'username', 'app_install', 30, 60, 'INSERT'),
    ('game_requests', 'requested_by', 'game_request', 3, 600, 'INSERT'),
    ('game_request_votes', 'username', 'game_request_vote', 30, 60, 'INSERT'),
    ('custom_nameplates', 'username', 'custom_nameplate', 5, 3600, 'INSERT OR UPDATE')
  ) as v(table_name, actor_column, action_name, max_hits, window_seconds, operations)
  loop
    if to_regclass('public.' || item.table_name) is not null then
      execute format('drop trigger if exists hbu_rate_%I_before on public.%I', item.action_name, item.table_name);
      execute format('drop trigger if exists hbu_rate_%I_after on public.%I', item.action_name, item.table_name);
      execute format(
        'create trigger %I before %s on public.%I for each row execute function public.hbu_guard_write_rate(%L, %L, %L, %L)',
        'hbu_rate_' || item.action_name || '_before', item.operations, item.table_name,
        item.actor_column, item.action_name, item.max_hits, item.window_seconds
      );
      execute format(
        'create trigger %I after %s on public.%I for each row execute function public.hbu_guard_write_rate(%L, %L, %L, %L)',
        'hbu_rate_' || item.action_name || '_after', item.operations, item.table_name,
        item.actor_column, item.action_name, item.max_hits, item.window_seconds
      );
    end if;
  end loop;
end;
$$;

-- Enforce RLS on sensitive tables if present, even if a previous setup missed it.
do $$
declare table_name text;
begin
  foreach table_name in array array[
    'accounts', 'messages', 'social_posts', 'social_likes', 'social_follows',
    'polls', 'poll_votes', 'shared_links', 'user_apps', 'app_installs',
    'ai_credits', 'app_purchases', 'custom_nameplates', 'game_requests',
    'game_request_votes', 'pets', 'clicker', 'quest_progress', 'typing'
  ] loop
    if to_regclass('public.' || table_name) is not null then
      execute format('alter table public.%I enable row level security', table_name);
    end if;
  end loop;
end;
$$;

-- Limit only debits. A transfer recipient's incoming coins do not consume quota.
do $$
begin
  if to_regclass('public.accounts') is not null then
    drop trigger if exists hbu_coin_debit_before on public.accounts;
    drop trigger if exists hbu_coin_debit_after on public.accounts;
    create trigger hbu_coin_debit_before before update of coins on public.accounts
      for each row execute function public.hbu_guard_coin_debit();
    create trigger hbu_coin_debit_after after update of coins on public.accounts
      for each row execute function public.hbu_guard_coin_debit();
  end if;
end;
$$;

-- The website already authenticates through send-message. Do not let copied
-- static clients brute-force passwords by calling hbu_login directly.
revoke execute on function public.hbu_login(text, text) from public, anon, authenticated;
grant execute on function public.hbu_login(text, text) to service_role;
revoke execute on function public.hbu_signup(text, text, text) from public, anon, authenticated;
grant execute on function public.hbu_signup(text, text, text) to service_role;

-- Keep sensitive tables inaccessible to direct browser writes. Their approved
-- RPCs / Edge Function paths perform authentication and validation.
revoke insert, update, delete on public.messages from public, anon, authenticated;
revoke all on public.accounts from public, anon, authenticated;
revoke all on public.social_posts, public.social_likes, public.social_follows from public, anon, authenticated;
revoke all on public.polls, public.poll_votes from public, anon, authenticated;
revoke all on public.shared_links from public, anon, authenticated;
revoke all on public.user_apps, public.app_installs, public.ai_credits, public.app_purchases from public, anon, authenticated;

-- Useful monitoring queries (run manually in SQL Editor):
-- Most active successful writes in the last hour:
-- select actor, action, count(*) as writes from public.hbu_write_events
-- where created_at > now() - interval '1 hour' group by actor, action order by writes desc;
-- Edge rate-limit buckets active in the last day:
-- select subject, action, sum(hits) as attempts from public.hbu_edge_rate_buckets
-- where window_start > extract(epoch from now() - interval '1 day')::bigint
-- group by subject, action order by attempts desc;
-- Cleanup old monitoring data (run periodically):
-- delete from public.hbu_write_events where created_at < now() - interval '30 days';
-- delete from public.hbu_edge_rate_buckets where window_start < extract(epoch from now() - interval '2 days')::bigint;

notify pgrst, 'reload schema';
