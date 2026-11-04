-- App Creator + App Store + AI credits + paid apps. Run once in the Supabase SQL editor (safe to run again). No Edge Function change for paid apps.
-- Safe to run again.

create table if not exists public.user_apps (
  id bigint generated always as identity primary key,
  owner text not null,
  name text not null default 'Untitled app',
  icon text,
  draft jsonb not null default '{}'::jsonb,   -- the working copy {html, css, js}
  live jsonb,                                 -- the published copy people run
  is_public boolean not null default false,   -- listed in the App Store
  version integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.app_installs (
  username text not null,
  app_id bigint not null references public.user_apps(id) on delete cascade,
  installed_at timestamptz not null default now(),
  primary key (username, app_id)
);
create table if not exists public.ai_credits (
  username text primary key,
  month text not null,
  used integer not null default 0,
  extra integer not null default 0
);
alter table public.user_apps enable row level security;
alter table public.app_installs enable row level security;
alter table public.ai_credits enable row level security;
revoke all on public.user_apps, public.app_installs, public.ai_credits from anon, authenticated;

-- ---------- AI credits (free monthly allowance + extra credits the owner gives) ----------
create or replace function public.hbu_ai_free() returns integer language sql immutable as $$ select 10 $$;

create or replace function public.hbu_ai_state(p_who text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r ai_credits%rowtype; m text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  insert into ai_credits (username, month) values (p_who, m) on conflict (username) do nothing;
  update ai_credits set month = m, used = 0 where username = p_who and month <> m;
  select * into r from ai_credits where username = p_who;
  return jsonb_build_object('free_left', greatest(public.hbu_ai_free() - r.used, 0), 'free_total', public.hbu_ai_free(), 'extra', r.extra);
end;
$$;

-- Server-only: spend one credit. Returns 'free' or 'extra' (so a failed request can be refunded).
create or replace function public.hbu_ai_take(p_who text) returns text
language plpgsql security definer set search_path = public as $$
begin
  perform public.hbu_ai_state(p_who);
  update ai_credits set used = used + 1 where username = p_who and used < public.hbu_ai_free();
  if found then return 'free'; end if;
  update ai_credits set extra = extra - 1 where username = p_who and extra > 0;
  if found then return 'extra'; end if;
  raise exception 'You are out of AI credits. Free credits come back next month.';
end;
$$;

create or replace function public.hbu_ai_refund(p_who text, p_kind text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_kind = 'extra' then update ai_credits set extra = extra + 1 where username = p_who;
  else update ai_credits set used = greatest(used - 1, 0) where username = p_who; end if;
end;
$$;

create or replace function public.hbu_ai_give(p_who text, p_amount integer) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public.hbu_ai_state(p_who);
  update ai_credits set extra = greatest(extra + p_amount, 0) where username = p_who;
  return public.hbu_ai_state(p_who);
end;
$$;
revoke all on function public.hbu_ai_state(text), public.hbu_ai_take(text), public.hbu_ai_refund(text, text), public.hbu_ai_give(text, integer) from public, anon, authenticated;
grant execute on function public.hbu_ai_state(text), public.hbu_ai_take(text), public.hbu_ai_refund(text, text), public.hbu_ai_give(text, integer) to service_role;

create or replace function public.hbu_ai_credits(p_username text, p_password text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  return public.hbu_ai_state(public.hbu_login(p_username, p_password));
end;
$$;

-- ---------- Paid apps ----------
alter table public.user_apps add column if not exists price integer not null default 0 check (price >= 0 and price <= 1000);
alter table public.user_apps add column if not exists price_per text not null default 'once' check (price_per in ('once', 'day'));
create table if not exists public.app_purchases (
  username text not null,
  app_id bigint not null references public.user_apps(id) on delete cascade,
  paid_until timestamptz,                    -- null = bought for good
  total_paid integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (username, app_id)
);
alter table public.app_purchases enable row level security;
alter table public.user_apps enable row level security;
alter table public.app_installs enable row level security;

-- Can this person run this app right now? Owners and free apps always; paid apps need a lifetime or unexpired purchase.
create or replace function public.hbu_app_unlocked(p_who text, p_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_apps a where a.id = p_id and (
    lower(a.owner) = lower(p_who) or a.price = 0
    or exists (select 1 from app_purchases u where u.app_id = a.id and u.username = p_who and (u.paid_until is null or u.paid_until > now()))
  ));
$$;
revoke all on function public.hbu_app_unlocked(text, bigint) from public, anon, authenticated;

drop function if exists public.hbu_app_publish(text, text, bigint, text, text, boolean);
drop function if exists public.hbu_app_mine(text, text);
drop function if exists public.hbu_app_store(text);
drop function if exists public.hbu_app_installed(text, text);

-- ---------- Apps ----------
-- Save the working copy (creates the app on first save).
create or replace function public.hbu_app_save(p_username text, p_password text, p_id bigint, p_draft jsonb)
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare who text; new_id bigint;
begin
  who := public.hbu_login(p_username, p_password);
  if p_draft is null or jsonb_typeof(p_draft) <> 'object' or length(p_draft::text) > 250000 then raise exception 'That app is too big (limit about 250 KB).'; end if;
  if p_id is null then
    if (select count(*) from user_apps where lower(owner) = lower(who)) >= 20 then raise exception 'You can have up to 20 apps. Delete one first.'; end if;
    insert into user_apps (owner, draft) values (who, p_draft) returning id into new_id;
    return new_id;
  end if;
  update user_apps set draft = p_draft, updated_at = now() where id = p_id and lower(owner) = lower(who);
  if not found then raise exception 'That app is not yours.'; end if;
  return p_id;
end;
$$;

-- Publish (or republish): the working copy becomes the live copy.
create or replace function public.hbu_app_publish(p_username text, p_password text, p_id bigint, p_name text, p_icon text, p_public boolean, p_price integer default 0, p_per text default 'once')
returns integer language plpgsql security definer set search_path = public, extensions as $$
declare who text; n text := trim(coalesce(p_name, '')); v integer;
begin
  who := public.hbu_login(p_username, p_password);
  if length(n) < 2 or length(n) > 24 then raise exception 'Give your app a name (2-24 characters).'; end if;
  if p_icon is not null and (p_icon !~ '^data:image/(png|webp|jpeg);base64,' or length(p_icon) > 50000) then raise exception 'That image is not allowed or is too big.'; end if;
  if coalesce(p_price, 0) < 0 or coalesce(p_price, 0) > 1000 then raise exception 'Price must be 0 to 1000 coins.'; end if;
  if coalesce(p_per, 'once') not in ('once', 'day') then raise exception 'Pick "once" or "per day".'; end if;
  begin
    if exists (select 1 from banned_words b where lower(n) like '%' || lower(b.word) || '%') then raise exception 'That name is not allowed.'; end if;
  exception when undefined_table then null;
  end;
  update user_apps set name = n, icon = p_icon, is_public = coalesce(p_public, false), live = draft,
         price = coalesce(p_price, 0), price_per = coalesce(p_per, 'once'),
         version = version + 1, updated_at = now()
   where id = p_id and lower(owner) = lower(who) returning version into v;
  if v is null then raise exception 'That app is not yours.'; end if;
  insert into app_installs (username, app_id) values (who, p_id) on conflict do nothing;
  return v;
end;
$$;

create or replace function public.hbu_app_mine(p_username text, p_password text)
returns table (id bigint, name text, icon text, is_public boolean, version integer, published boolean, updated_at timestamptz, price integer, price_per text)
language plpgsql security definer set search_path = public, extensions as $$
declare who text;
begin
  who := public.hbu_login(p_username, p_password);
  return query select a.id, a.name, a.icon, a.is_public, a.version, a.live is not null, a.updated_at, a.price, a.price_per
    from user_apps a where lower(a.owner) = lower(who) order by a.updated_at desc;
end;
$$;

-- One app's code. p_draft = true gives the working copy (owner only).
create or replace function public.hbu_app_get(p_username text, p_password text, p_id bigint, p_draft boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; a user_apps%rowtype; mine boolean;
begin
  who := public.hbu_login(p_username, p_password);
  select * into a from user_apps where id = p_id;
  if a.id is null then raise exception 'That app no longer exists.'; end if;
  mine := lower(a.owner) = lower(who);
  if p_draft then
    if not mine then raise exception 'That app is not yours.'; end if;
    return jsonb_build_object('id', a.id, 'name', a.name, 'icon', a.icon, 'owner', a.owner, 'version', a.version,
      'is_public', a.is_public, 'published', a.live is not null, 'price', a.price, 'price_per', a.price_per, 'code', a.draft);
  end if;
  if a.live is null or not (a.is_public or mine or exists (select 1 from app_installs i where i.app_id = a.id and i.username = who)) then
    raise exception 'That app is not available.';
  end if;
  if not public.hbu_app_unlocked(who, a.id) then
    return jsonb_build_object('id', a.id, 'name', a.name, 'owner', a.owner, 'locked', true, 'price', a.price, 'price_per', a.price_per);
  end if;
  return jsonb_build_object('id', a.id, 'name', a.name, 'icon', a.icon, 'owner', a.owner, 'version', a.version, 'price', a.price, 'price_per', a.price_per, 'code', a.live);
end;
$$;

-- The App Store: public apps, no login needed. Code is not included.
create or replace function public.hbu_app_store(p_search text default null)
returns table (id bigint, name text, icon text, owner text, version integer, installs bigint, updated_at timestamptz, price integer, price_per text)
language sql security definer set search_path = public as $$
  select a.id, a.name, a.icon, a.owner, a.version, (select count(*) from app_installs i where i.app_id = a.id), a.updated_at, a.price, a.price_per
    from user_apps a
   where a.is_public and a.live is not null
     and (p_search is null or p_search = '' or lower(a.name) like '%' || lower(p_search) || '%' or lower(a.owner) like '%' || lower(p_search) || '%')
   order by (select count(*) from app_installs i where i.app_id = a.id) desc, a.updated_at desc
   limit 60;
$$;

create or replace function public.hbu_app_installed(p_username text, p_password text)
returns table (id bigint, name text, icon text, owner text, version integer, mine boolean, price integer, price_per text, unlocked boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare who text;
begin
  who := public.hbu_login(p_username, p_password);
  return query select a.id, a.name, a.icon, a.owner, a.version, lower(a.owner) = lower(who), a.price, a.price_per, public.hbu_app_unlocked(who, a.id)
    from app_installs i join user_apps a on a.id = i.app_id
   where i.username = who and a.live is not null and (a.is_public or lower(a.owner) = lower(who))
   order by i.installed_at;
end;
$$;

create or replace function public.hbu_app_install(p_username text, p_password text, p_id bigint, p_on boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; a user_apps%rowtype;
begin
  who := public.hbu_login(p_username, p_password);
  if not p_on then
    delete from app_installs where username = who and app_id = p_id;
    return;
  end if;
  select * into a from user_apps where id = p_id;
  if a.id is null or a.live is null or not (a.is_public or lower(a.owner) = lower(who)) then raise exception 'That app is not available.'; end if;
  if (select count(*) from app_installs where username = who) >= 40 then raise exception 'You can install up to 40 apps.'; end if;
  insert into app_installs (username, app_id) values (who, p_id) on conflict do nothing;
end;
$$;

-- Buy an app (or more days of it). The coins go straight to the creator.
create or replace function public.hbu_app_buy(p_username text, p_password text, p_id bigint, p_days integer default 1)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; a user_apps%rowtype; cost integer; until_ts timestamptz; cur timestamptz; bal integer; days integer := greatest(1, least(coalesce(p_days, 1), 30));
begin
  who := public.hbu_login(p_username, p_password);
  select * into a from user_apps where id = p_id for update;
  if a.id is null or a.live is null or not (a.is_public or lower(a.owner) = lower(who)) then raise exception 'That app is not available.'; end if;
  if lower(a.owner) = lower(who) or a.price = 0 then raise exception 'You do not need to buy this one.'; end if;
  if a.price_per = 'day' then
    cost := a.price * days;
    select paid_until into cur from app_purchases where username = who and app_id = a.id;
    until_ts := greatest(now(), coalesce(cur, now())) + make_interval(days => days);
  else
    if exists (select 1 from app_purchases where username = who and app_id = a.id and paid_until is null) then raise exception 'You already own this app.'; end if;
    cost := a.price;
    until_ts := null;
  end if;
  update accounts set coins = coins - cost where username = who and coins >= cost returning coins into bal;
  if bal is null then raise exception 'Not enough coins (you need %).', cost; end if;
  update accounts set coins = coins + cost where lower(username) = lower(a.owner);
  insert into app_purchases (username, app_id, paid_until, total_paid) values (who, a.id, until_ts, cost)
    on conflict (username, app_id) do update set paid_until = excluded.paid_until, total_paid = app_purchases.total_paid + cost, updated_at = now();
  insert into app_installs (username, app_id) values (who, a.id) on conflict do nothing;
  return jsonb_build_object('coins', bal, 'paid', cost, 'paid_until', until_ts);
end;
$$;

-- Owners can delete their apps. Moderators/admins (staff roles) and Rocky can remove anyone's.
create or replace function public.hbu_app_delete(p_username text, p_password text, p_id bigint)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; a user_apps%rowtype; r text; staff boolean := false;
begin
  who := public.hbu_login(p_username, p_password);
  select * into a from user_apps where id = p_id;
  if a.id is null then return; end if;
  select role into r from accounts where username = who;
  begin
    select coalesce(bool_or(c.staff), false) into staff from custom_roles c where c.name = r;
  exception when undefined_table then staff := false;
  end;
  if lower(a.owner) <> lower(who) and not staff and lower(who) <> 'rocky' then raise exception 'You can only delete your own apps.'; end if;
  delete from user_apps where id = p_id;
end;
$$;

grant execute on function public.hbu_ai_credits(text, text), public.hbu_app_save(text, text, bigint, jsonb),
  public.hbu_app_publish(text, text, bigint, text, text, boolean, integer, text), public.hbu_app_mine(text, text),
  public.hbu_app_get(text, text, bigint, boolean), public.hbu_app_store(text), public.hbu_app_installed(text, text),
  public.hbu_app_install(text, text, bigint, boolean), public.hbu_app_delete(text, text, bigint),
  public.hbu_app_buy(text, text, bigint, integer) to anon, authenticated;
notify pgrst, 'reload schema';
