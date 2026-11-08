-- HBU coins, daily wheel and name plates. Run once in the Supabase SQL editor.
-- No Edge Function change is needed; everything goes through these functions.

alter table public.accounts add column if not exists coins integer not null default 0 check (coins >= 0);
alter table public.accounts add column if not exists last_spin date;
alter table public.accounts add column if not exists owned_plates text[] not null default '{}';
alter table public.accounts add column if not exists active_plate text;

create table if not exists public.plates (
  id text primary key,
  name text not null,
  price integer not null check (price >= 0),
  name_color text not null,
  bg text not null,
  sort integer not null default 0
);
alter table public.plates enable row level security;
drop policy if exists "plates are public" on public.plates;
create policy "plates are public" on public.plates for select using (true);
grant select on public.plates to anon, authenticated;

insert into public.plates (id, name, price, name_color, bg, sort) values
  ('neon-pink', 'Neon Pink',    100, '#ff7ad9', 'rgba(255,95,210,.22)', 1),
  ('ocean',     'Ocean',        150, '#6fe3ff', 'rgba(61,217,255,.2)', 2),
  ('toxic',     'Toxic',        200, '#8dff7a', 'rgba(110,255,90,.18)', 3),
  ('ember',     'Ember',        300, '#ffb347', 'linear-gradient(105deg, rgba(255,120,40,.35), rgba(255,60,60,.25))', 4),
  ('gold',      'Gold',         500, '#ffe066', 'linear-gradient(105deg, rgba(255,214,70,.38), rgba(190,130,20,.25))', 5),
  ('galaxy',    'Galaxy',       750, '#d9b8ff', 'linear-gradient(105deg, rgba(88,40,200,.55), rgba(220,60,200,.3))', 6),
  ('rainbow',   'Rainbow',     1000, '#ffffff', 'linear-gradient(105deg, rgba(255,60,60,.35), rgba(255,200,40,.3), rgba(60,255,120,.3), rgba(60,160,255,.35), rgba(190,90,255,.35))', 7),
  ('arctic',    'Arctic Ice',   175, '#bff5ff', 'linear-gradient(105deg, rgba(32,115,180,.55), rgba(135,230,255,.3))', 8),
  ('sunset',    'Sunset',       250, '#ffd0a3', 'linear-gradient(105deg, rgba(245,90,70,.5), rgba(234,124,39,.32))', 9),
  ('forest',    'Enchanted Forest', 350, '#b4ffbd', 'linear-gradient(105deg, rgba(15,100,65,.6), rgba(55,160,92,.32))', 10),
  ('lavender',  'Lavender Dream', 400, '#f0d7ff', 'linear-gradient(105deg, rgba(127,72,194,.58), rgba(220,133,235,.3))', 11),
  ('storm',     'Thunderstorm', 450, '#d7eaff', 'linear-gradient(105deg, rgba(38,51,96,.7), rgba(88,112,150,.4))', 12),
  ('cherry',    'Cherry Blossom', 550, '#ffd7ec', 'linear-gradient(105deg, rgba(198,53,112,.55), rgba(255,161,205,.3))', 13),
  ('aurora',    'Aurora',       650, '#c6ffe9', 'linear-gradient(105deg, rgba(29,147,148,.55), rgba(105,71,196,.48), rgba(50,185,122,.35))', 14),
  ('inferno',   'Inferno',      800, '#ffe1a3', 'linear-gradient(105deg, rgba(155,35,29,.7), rgba(255,125,23,.4))', 15),
  ('cosmic',    'Cosmic Nebula', 900, '#e8d0ff', 'linear-gradient(105deg, rgba(40,25,105,.72), rgba(163,49,164,.48), rgba(45,99,184,.45))', 16),
  ('diamond',   'Diamond',     1200, '#e9fcff', 'linear-gradient(105deg, rgba(31,127,164,.65), rgba(169,236,255,.38), rgba(87,130,208,.48))', 17)
on conflict (id) do update
  set name = excluded.name, price = excluded.price, name_color = excluded.name_color, bg = excluded.bg, sort = excluded.sort;

create or replace function public.hbu_wallet(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; a accounts%rowtype; today date := (now() at time zone 'utc')::date;
begin
  who := public.hbu_login(p_username, p_password);
  select * into a from accounts where username = who;
  return jsonb_build_object(
    'coins', a.coins,
    'owned', to_jsonb(a.owned_plates),
    'active', a.active_plate,
    'can_spin', a.last_spin is null or a.last_spin < today,
    'next_spin', ((today + 1)::timestamp at time zone 'utc')
  );
end;
$$;

-- One spin per UTC day. The prize is chosen here, never by the browser.
create or replace function public.hbu_spin(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; today date := (now() at time zone 'utc')::date; roll int := floor(random() * 100)::int; prize int; total int;
begin
  who := public.hbu_login(p_username, p_password);
  prize := case when roll < 35 then 10 when roll < 65 then 25 when roll < 83 then 50
                when roll < 93 then 75 when roll < 98 then 100 else 250 end;
  update accounts set coins = coins + prize, last_spin = today
   where username = who and (last_spin is null or last_spin < today)
   returning coins into total;
  if total is null then raise exception 'You already spun today. Come back tomorrow!'; end if;
  return jsonb_build_object('prize', prize, 'coins', total);
end;
$$;

create or replace function public.hbu_buy_plate(p_username text, p_password text, p_plate text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; cost int; total int;
begin
  who := public.hbu_login(p_username, p_password);
  select price into cost from plates where id = p_plate;
  if cost is null then raise exception 'Unknown name plate'; end if;
  update accounts set coins = coins - cost, owned_plates = array_append(owned_plates, p_plate)
   where username = who and coins >= cost and not (p_plate = any(owned_plates))
   returning coins into total;
  if total is null then raise exception 'Not enough coins, or you already own it'; end if;
  return jsonb_build_object('coins', total);
end;
$$;

-- p_plate = '' takes the plate off.
create or replace function public.hbu_equip_plate(p_username text, p_password text, p_plate text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text;
begin
  who := public.hbu_login(p_username, p_password);
  if coalesce(p_plate, '') = '' then
    update accounts set active_plate = null where username = who;
  else
    update accounts set active_plate = p_plate where username = who and p_plate = any(owned_plates);
    if not found then raise exception 'You do not own that name plate'; end if;
  end if;
end;
$$;

-- Public: which plate each player wears (used to colour the chat).
create or replace function public.hbu_plates()
returns table (username text, plate text) language sql security definer set search_path = public as $$
  select username, active_plate from accounts where active_plate is not null;
$$;

grant execute on function
  public.hbu_wallet(text, text),
  public.hbu_spin(text, text),
  public.hbu_buy_plate(text, text, text),
  public.hbu_equip_plate(text, text, text),
  public.hbu_plates()
to anon, authenticated;

notify pgrst, 'reload schema';
