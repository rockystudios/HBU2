-- HBU2 device security and active-user presence.
-- Run in Supabase SQL Editor before deploying the updated Edge Function.
create table if not exists public.hbu_devices (
  device_id text primary key check (device_id ~ '^[a-f0-9-]{36}$'),
  banned boolean not null default false,
  ban_reason text,
  created_at timestamptz not null default now(),
  banned_at timestamptz
);
create table if not exists public.hbu_device_accounts (
  device_id text not null references public.hbu_devices(device_id) on delete cascade,
  username text not null,
  linked_at timestamptz not null default now(),
  primary key (device_id, username)
);
create index if not exists hbu_device_accounts_username_idx on public.hbu_device_accounts(lower(username));
create table if not exists public.hbu_presence (
  username text primary key,
  last_seen timestamptz not null default now()
);
alter table public.hbu_devices enable row level security;
alter table public.hbu_device_accounts enable row level security;
alter table public.hbu_presence enable row level security;

create or replace function public.hbu_device_signup_check(p_device_id text, p_username text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare used_count integer;
begin
  if coalesce(p_device_id, '') !~ '^[a-f0-9-]{36}$' then raise exception 'This browser could not identify its device. Refresh and try again.'; end if;
  insert into hbu_devices(device_id) values (p_device_id) on conflict do nothing;
  if exists (select 1 from hbu_devices where device_id = p_device_id and banned) then
    raise exception 'This device is blocked from creating or using HBU accounts.';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_device_id));
  select count(distinct username) into used_count from hbu_device_accounts where device_id = p_device_id;
  if not exists (select 1 from hbu_device_accounts where device_id = p_device_id and lower(username) = lower(p_username))
     and used_count >= 2 then
    raise exception 'This device has reached its limit of two HBU accounts.';
  end if;
end;
$$;

create or replace function public.hbu_device_attach(p_username text, p_password text, p_device_id text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; used_count integer;
begin
  who := public.hbu_login(p_username, p_password);
  if coalesce(p_device_id, '') !~ '^[a-f0-9-]{36}$' then raise exception 'Device verification is required. Refresh the page and log in again.'; end if;
  insert into hbu_devices(device_id) values (p_device_id) on conflict do nothing;
  if exists (select 1 from hbu_devices where device_id = p_device_id and banned) then raise exception 'This device is blocked from using HBU accounts.'; end if;
  perform pg_advisory_xact_lock(hashtext(p_device_id));
  select count(distinct username) into used_count from hbu_device_accounts where device_id = p_device_id;
  if not exists (select 1 from hbu_device_accounts where device_id = p_device_id and lower(username) = lower(who))
     and used_count >= 2 then raise exception 'This device has reached its limit of two HBU accounts.'; end if;
  insert into hbu_device_accounts(device_id, username) values (p_device_id, who) on conflict do nothing;
end;
$$;

create or replace function public.hbu_owner_device_ban(p_username text, p_password text, p_target_username text, p_reason text default null)
returns integer language plpgsql security definer set search_path = public, extensions as $$
declare who text; affected integer;
begin
  who := public.hbu_login(p_username, p_password);
  if lower(who) <> 'rocky' then raise exception 'Only the owner can device-ban accounts.'; end if;
  update hbu_devices d set banned = true, ban_reason = left(coalesce(p_reason, 'Owner device ban'), 200), banned_at = now()
  where d.device_id in (
    select da.device_id from hbu_device_accounts da where lower(da.username) = lower(trim(p_target_username))
  );
  get diagnostics affected = row_count;
  if affected = 0 then raise exception 'No registered device was found for that username.'; end if;
  return affected;
end;
$$;

create or replace function public.hbu_presence_ping(p_username text, p_password text, p_device_id text default null)
returns integer language plpgsql security definer set search_path = public, extensions as $$
declare who text; n integer;
begin
  who := public.hbu_login(p_username, p_password);
  insert into hbu_presence(username, last_seen) values (who, now())
  on conflict (username) do update set last_seen = excluded.last_seen;
  delete from hbu_presence where last_seen < now() - interval '3 minutes';
  select count(*) into n from hbu_presence where last_seen >= now() - interval '2 minutes';
  return n;
end;
$$;

revoke all on function public.hbu_device_signup_check(text,text) from public;
revoke all on function public.hbu_device_attach(text,text,text) from public;
revoke all on function public.hbu_owner_device_ban(text,text,text,text) from public;
revoke all on function public.hbu_presence_ping(text,text,text) from public;
grant execute on function public.hbu_device_signup_check(text,text),
  public.hbu_device_attach(text,text,text),
  public.hbu_owner_device_ban(text,text,text,text),
  public.hbu_presence_ping(text,text,text) to anon, authenticated;
notify pgrst, 'reload schema';
