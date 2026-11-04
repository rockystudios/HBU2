-- Pet, Clicker, Achievements and Game Requests apps. Run once in the Supabase SQL editor.
-- No Edge Function change needed. Safe to run again. (Run quests.sql, links.sql and app-creator.sql too if you want
-- their achievements to count; achievements for tables that don't exist yet simply stay at 0.)

-- ---------------------------------------------------------------- helpers
create or replace function public.hbu_is_staff(p_who text)
returns boolean language plpgsql security definer set search_path = public as $$
declare ok boolean := false;
begin
  if lower(p_who) = 'rocky' then return true; end if;
  begin
    select coalesce(r.staff, false) into ok
      from accounts a join custom_roles r on r.name = a.role where a.username = p_who;
  exception when others then
    select coalesce(a.role in ('mod', 'administrator'), false) into ok from accounts a where a.username = p_who;
  end;
  return coalesce(ok, false);
end;
$$;
revoke all on function public.hbu_is_staff(text) from public, anon, authenticated;

create or replace function public.hbu_name_ok(p_text text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  return not exists (select 1 from banned_words b where lower(p_text) like '%' || lower(b.word) || '%');
exception when others then
  return true;
end;
$$;
revoke all on function public.hbu_name_ok(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- Pet
create table if not exists public.pets (
  username text primary key,
  name text not null,
  species text not null,
  xp integer not null default 0,
  fullness integer not null default 70,
  joy integer not null default 70,
  fed_at timestamptz not null default now(),
  played_at timestamptz not null default now(),
  last_play timestamptz,
  created_at timestamptz not null default now()
);
alter table public.pets enable row level security;
revoke all on public.pets from anon, authenticated;

-- Fullness drops 4 per hour and joy 3 per hour. Pets never die, they just get sad.
create or replace function public.hbu_pet_json(p public.pets)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'name', p.name, 'species', p.species, 'xp', p.xp,
    'level', p.xp / 50 + 1, 'next_xp', (p.xp / 50 + 1) * 50,
    'fullness', greatest(0, p.fullness - floor(extract(epoch from now() - p.fed_at) / 3600 * 4)::int),
    'joy', greatest(0, p.joy - floor(extract(epoch from now() - p.played_at) / 3600 * 3)::int),
    'play_wait', greatest(0, 300 - floor(extract(epoch from now() - coalesce(p.last_play, now() - interval '1 day')))::int)
  );
$$;

create or replace function public.hbu_pet_get(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; p pets%rowtype; c int;
begin
  who := public.hbu_login(p_username, p_password);
  select coins into c from accounts where username = who;
  select * into p from pets where username = who;
  return jsonb_build_object('coins', c, 'pet', case when p.username is null then null else public.hbu_pet_json(p) end);
end;
$$;

create or replace function public.hbu_pet_adopt(p_username text, p_password text, p_name text, p_species text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; n text := trim(coalesce(p_name, '')); have int; p pets%rowtype;
begin
  who := public.hbu_login(p_username, p_password);
  if p_species is null or p_species <> all (array['cat','dog','fox','dragon','bunny','panda','alien','frog']) then
    raise exception 'Pick one of the pets.';
  end if;
  if length(n) < 2 or length(n) > 16 then raise exception 'Name your pet (2-16 characters).'; end if;
  if not public.hbu_name_ok(n) then raise exception 'That name is not allowed.'; end if;
  if exists (select 1 from pets where username = who) then raise exception 'You already have a pet.'; end if;
  select coins into have from accounts where username = who for update;
  if have < 100 then raise exception 'Adopting costs 100 coins.'; end if;
  update accounts set coins = coins - 100 where username = who returning coins into have;
  insert into pets (username, name, species) values (who, n, p_species) returning * into p;
  return jsonb_build_object('coins', have, 'pet', public.hbu_pet_json(p));
end;
$$;

create or replace function public.hbu_pet_feed(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; p pets%rowtype; have int; cur int;
begin
  who := public.hbu_login(p_username, p_password);
  select * into p from pets where username = who for update;
  if p.username is null then raise exception 'Adopt a pet first.'; end if;
  cur := (public.hbu_pet_json(p)->>'fullness')::int;
  if cur >= 90 then raise exception '% is too full right now.', p.name; end if;
  select coins into have from accounts where username = who for update;
  if have < 5 then raise exception 'Food costs 5 coins.'; end if;
  update accounts set coins = coins - 5 where username = who returning coins into have;
  update pets set fullness = least(100, cur + 35), fed_at = now(), xp = xp + 5 where username = who returning * into p;
  return jsonb_build_object('coins', have, 'pet', public.hbu_pet_json(p));
end;
$$;

create or replace function public.hbu_pet_play(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; p pets%rowtype; cur int; c int;
begin
  who := public.hbu_login(p_username, p_password);
  select * into p from pets where username = who for update;
  if p.username is null then raise exception 'Adopt a pet first.'; end if;
  if (public.hbu_pet_json(p)->>'play_wait')::int > 0 then raise exception '% needs a little rest. Try again soon.', p.name; end if;
  cur := (public.hbu_pet_json(p)->>'joy')::int;
  update pets set joy = least(100, cur + 30), played_at = now(), last_play = now(), xp = xp + 3 where username = who returning * into p;
  select coins into c from accounts where username = who;
  return jsonb_build_object('coins', c, 'pet', public.hbu_pet_json(p));
end;
$$;

create or replace function public.hbu_pet_rename(p_username text, p_password text, p_name text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; n text := trim(coalesce(p_name, '')); p pets%rowtype; c int;
begin
  who := public.hbu_login(p_username, p_password);
  if length(n) < 2 or length(n) > 16 then raise exception 'Name your pet (2-16 characters).'; end if;
  if not public.hbu_name_ok(n) then raise exception 'That name is not allowed.'; end if;
  update pets set name = n where username = who returning * into p;
  if p.username is null then raise exception 'Adopt a pet first.'; end if;
  select coins into c from accounts where username = who;
  return jsonb_build_object('coins', c, 'pet', public.hbu_pet_json(p));
end;
$$;

-- ---------------------------------------------------------------- Clicker
-- Bits are separate from coins. The server limits clicks to ~10 per second, adds idle income (max 8 hours),
-- and turning bits into coins is slow and capped per day, so it can't wreck the coin economy.
create table if not exists public.clicker (
  username text primary key,
  bits bigint not null default 0,
  total_bits bigint not null default 0,
  tap integer not null default 0,
  auto integer not null default 0,
  last_sync timestamptz not null default now(),
  cash_day date,
  cash_today integer not null default 0
);
alter table public.clicker enable row level security;
revoke all on public.clicker from anon, authenticated;

create or replace function public.hbu_clicker_json(c public.clicker, p_coins integer)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'bits', c.bits, 'total', c.total_bits, 'tap', c.tap, 'auto', c.auto,
    'tap_cost', case when c.tap >= 30 then null else floor(20 * power(1.6, c.tap))::bigint end,
    'auto_cost', case when c.auto >= 30 then null else floor(50 * power(1.5, c.auto))::bigint end,
    'per_click', 1 + c.tap, 'per_sec', c.auto,
    'rate', 2500, 'cap', 15,
    'cashed_today', case when c.cash_day = (now() at time zone 'utc')::date then c.cash_today else 0 end,
    'coins', p_coins
  );
$$;

create or replace function public.hbu_clicker(p_username text, p_password text, p_clicks integer default 0, p_buy text default null, p_cash boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  who text; c clicker%rowtype; el numeric; ok_clicks int; gain bigint; cost bigint; take int; paid int := 0;
  skipped boolean := false; today date := (now() at time zone 'utc')::date; cn int;
begin
  who := public.hbu_login(p_username, p_password);
  insert into clicker (username) values (who) on conflict do nothing;
  select * into c from clicker where username = who for update;
  el := least(extract(epoch from now() - c.last_sync), 28800);
  if el < 1 and p_buy is null and not p_cash then
    skipped := true;
  else
    ok_clicks := greatest(0, least(coalesce(p_clicks, 0), floor(el * 10)::int + 5, 500));
    gain := ok_clicks::bigint * (1 + c.tap) + floor(el * c.auto)::bigint;
    c.bits := c.bits + gain;
    c.total_bits := c.total_bits + gain;
    c.last_sync := now();
    if p_buy = 'tap' then
      if c.tap >= 30 then raise exception 'Already maxed out.'; end if;
      cost := floor(20 * power(1.6, c.tap))::bigint;
      if c.bits < cost then raise exception 'Not enough bits.'; end if;
      c.bits := c.bits - cost; c.tap := c.tap + 1;
    elsif p_buy = 'auto' then
      if c.auto >= 30 then raise exception 'Already maxed out.'; end if;
      cost := floor(50 * power(1.5, c.auto))::bigint;
      if c.bits < cost then raise exception 'Not enough bits.'; end if;
      c.bits := c.bits - cost; c.auto := c.auto + 1;
    elsif p_buy is not null then
      raise exception 'Unknown upgrade.';
    end if;
    if p_cash then
      if c.cash_day is distinct from today then c.cash_day := today; c.cash_today := 0; end if;
      if c.cash_today >= 15 then raise exception 'Daily cash-out limit reached (15 coins). Come back tomorrow!'; end if;
      take := least((c.bits / 2500)::int, 15 - c.cash_today);
      if take < 1 then
        raise exception 'Nothing to cash out: you need 2,500 bits per coin (max 15 coins a day, %/15 used).', c.cash_today;
      end if;
      c.bits := c.bits - take::bigint * 2500;
      c.cash_today := c.cash_today + take;
      update accounts set coins = coins + take where username = who;
      paid := take;
    end if;
    update clicker set bits = c.bits, total_bits = c.total_bits, tap = c.tap, auto = c.auto, last_sync = c.last_sync,
      cash_day = c.cash_day, cash_today = c.cash_today where username = who;
  end if;
  select coins into cn from accounts where username = who;
  return public.hbu_clicker_json(c, cn) || jsonb_build_object('skipped', skipped, 'paid', paid);
end;
$$;

-- ---------------------------------------------------------------- Game requests
create table if not exists public.game_requests (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  requested_by text not null,
  title text not null,
  note text,
  status text not null default 'open' check (status in ('open', 'added', 'declined')),
  votes integer not null default 0
);
create table if not exists public.game_request_votes (
  request_id bigint not null references public.game_requests(id) on delete cascade,
  username text not null,
  primary key (request_id, username)
);
alter table public.game_requests enable row level security;
alter table public.game_request_votes enable row level security;
revoke all on public.game_requests, public.game_request_votes from anon, authenticated;

-- Anyone can read. If valid login details are given, "voted" and "mine" are filled in too.
create or replace function public.hbu_requests_get(p_username text default null, p_password text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text := null; staff boolean := false;
begin
  if p_username is not null and p_password is not null then
    begin who := public.hbu_login(p_username, p_password); exception when others then who := null; end;
  end if;
  if who is not null then staff := public.hbu_is_staff(who); end if;
  return jsonb_build_object('staff', staff, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'title', r.title, 'note', r.note, 'by', r.requested_by, 'status', r.status, 'votes', r.votes,
      'voted', who is not null and exists (select 1 from game_request_votes v where v.request_id = r.id and v.username = who),
      'mine', who is not null and lower(r.requested_by) = lower(who)
    ) order by (r.status = 'open') desc, r.votes desc, r.created_at desc)
    from (select * from game_requests order by (status = 'open') desc, votes desc, created_at desc limit 100) r
  ), '[]'::jsonb));
end;
$$;

create or replace function public.hbu_request_post(p_username text, p_password text, p_title text, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; t text := trim(coalesce(p_title, '')); n text := nullif(trim(coalesce(p_note, '')), ''); rid bigint;
begin
  who := public.hbu_login(p_username, p_password);
  if length(t) < 2 or length(t) > 60 then raise exception 'Name the game (2-60 characters).'; end if;
  if n is not null and length(n) > 200 then raise exception 'Keep the note under 200 characters.'; end if;
  if not public.hbu_name_ok(t || ' ' || coalesce(n, '')) then raise exception 'Please keep it school-friendly.'; end if;
  if exists (select 1 from game_requests where lower(title) = lower(t) and status = 'open') then
    raise exception 'That game was already requested. Go vote for it!';
  end if;
  if (select count(*) from game_requests where lower(requested_by) = lower(who) and created_at > now() - interval '1 day') >= 3 then
    raise exception 'You can request 3 games a day.';
  end if;
  insert into game_requests (requested_by, title, note, votes) values (who, t, n, 1) returning id into rid;
  insert into game_request_votes (request_id, username) values (rid, who);
end;
$$;

create or replace function public.hbu_request_vote(p_username text, p_password text, p_id bigint)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; r game_requests%rowtype;
begin
  who := public.hbu_login(p_username, p_password);
  select * into r from game_requests where id = p_id for update;
  if r.id is null then raise exception 'That request is gone.'; end if;
  if r.status <> 'open' then raise exception 'Voting is closed for this one.'; end if;
  if exists (select 1 from game_request_votes where request_id = p_id and username = who) then
    delete from game_request_votes where request_id = p_id and username = who;
  else
    insert into game_request_votes (request_id, username) values (p_id, who);
  end if;
  update game_requests set votes = (select count(*) from game_request_votes where request_id = p_id) where id = p_id;
end;
$$;

create or replace function public.hbu_request_set(p_username text, p_password text, p_id bigint, p_status text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text;
begin
  who := public.hbu_login(p_username, p_password);
  if not public.hbu_is_staff(who) then raise exception 'Only staff can do that.'; end if;
  if p_status not in ('open', 'added', 'declined') then raise exception 'Unknown status.'; end if;
  update game_requests set status = p_status where id = p_id;
end;
$$;

create or replace function public.hbu_request_delete(p_username text, p_password text, p_id bigint)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; r game_requests%rowtype;
begin
  who := public.hbu_login(p_username, p_password);
  select * into r from game_requests where id = p_id;
  if r.id is null then return; end if;
  if lower(r.requested_by) <> lower(who) and not public.hbu_is_staff(who) then raise exception 'You can only remove your own requests.'; end if;
  delete from game_requests where id = p_id;
end;
$$;

-- ---------------------------------------------------------------- Achievements
create table if not exists public.achievements (
  username text not null,
  key text not null,
  unlocked_at timestamptz not null default now(),
  primary key (username, key)
);
alter table public.achievements enable row level security;
revoke all on public.achievements from anon, authenticated;

-- Counts something for one account; returns 0 if that app's table hasn't been created yet.
create or replace function public.hbu_ach_count(p_sql text, p_who text)
returns integer language plpgsql security definer set search_path = public as $$
declare n bigint;
begin
  execute p_sql using p_who into n;
  return least(coalesce(n, 0), 2000000000)::int;
exception when others then
  return 0;
end;
$$;
revoke all on function public.hbu_ach_count(text, text) from public, anon, authenticated;

-- Unlocking happens here, once, and pays the coin reward once.
create or replace function public.hbu_achievements(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  who text; stats jsonb; a record; v int; newly jsonb := '[]'::jsonb; got int; total int;
begin
  who := public.hbu_login(p_username, p_password);
  stats := jsonb_build_object(
    'msgs',   public.hbu_ach_count('select count(*) from messages where "user" = $1 and receiver = ''everyone''', who),
    'streak', public.hbu_ach_count('select best_streak from accounts where username = $1', who),
    'coins',  public.hbu_ach_count('select coins from accounts where username = $1', who),
    'quests', public.hbu_ach_count('select count(*) from quest_progress where username = $1 and claimed', who),
    'links',  public.hbu_ach_count('select count(*) from shared_links where lower(posted_by) = lower($1)', who),
    'apps',   public.hbu_ach_count('select count(*) from user_apps where lower(owner) = lower($1) and live is not null', who),
    'pet',    public.hbu_ach_count('select xp / 50 + 1 from pets where username = $1', who),
    'bits',   public.hbu_ach_count('select total_bits from clicker where username = $1', who),
    'reqs',   public.hbu_ach_count('select count(*) from game_requests where lower(requested_by) = lower($1)', who)
  );
  for a in select * from public.hbu_ach_list() loop
    v := (stats->>a.stat)::int;
    if v >= a.goal then
      insert into achievements (username, key) values (who, a.key) on conflict do nothing;
      get diagnostics got = row_count;
      if got = 1 then
        update accounts set coins = coins + a.reward where username = who;
        newly := newly || jsonb_build_array(jsonb_build_object('title', a.title, 'icon', a.icon, 'reward', a.reward));
      end if;
    end if;
  end loop;
  select coins into total from accounts where username = who;
  return jsonb_build_object('coins', total, 'new', newly, 'list', (
    select jsonb_agg(jsonb_build_object(
      'key', l.key, 'title', l.title, 'desc', l.descr, 'icon', l.icon, 'goal', l.goal, 'reward', l.reward,
      'progress', least(l.goal, (stats->>l.stat)::int), 'unlocked', u.key is not null
    ) order by (u.key is null), l.sort)
    from public.hbu_ach_list() l left join achievements u on u.key = l.key and u.username = who
  ));
end;
$$;

create or replace function public.hbu_ach_list()
returns table (sort int, key text, title text, descr text, icon text, stat text, goal int, reward int)
language sql immutable as $$
  select row_number() over ()::int, * from (values
    ('chat_1',    'First words',     'Send a message in the main chat',     '💬', 'msgs',   1,    10),
    ('chat_100',  'Chatterbox',      'Send 100 messages in the main chat',  '🗣️', 'msgs',   100,  50),
    ('chat_1000', 'Chat legend',     'Send 1,000 messages in the main chat','📣', 'msgs',   1000, 250),
    ('streak_3',  'On a roll',       'Reach a 3-day spin streak',           '🔥', 'streak', 3,    25),
    ('streak_7',  'Week warrior',    'Reach a 7-day spin streak',           '⚡', 'streak', 7,    75),
    ('streak_30', 'Unstoppable',     'Reach a 30-day spin streak',          '👑', 'streak', 30,   300),
    ('coins_500', 'Saver',           'Hold 500 coins at once',              '💰', 'coins',  500,  25),
    ('coins_5k',  'Big spender',     'Hold 5,000 coins at once',            '💎', 'coins',  5000, 100),
    ('quest_1',   'Quest starter',   'Claim a quest',                       '🎯', 'quests', 1,    15),
    ('quest_25',  'Quest master',    'Claim 25 quests',                     '🏆', 'quests', 25,   150),
    ('link_1',    'Sharer',          'Post an unblocked link',              '🔗', 'links',  1,    10),
    ('link_10',   'Link hero',       'Post 10 unblocked links',             '🌐', 'links',  10,   75),
    ('app_1',     'Maker',           'Publish an app in App Creator',       '🛠️', 'apps',   1,    50),
    ('pet_1',     'Pet parent',      'Adopt a pet',                         '🐾', 'pet',    1,    15),
    ('pet_5',     'Pet whisperer',   'Get your pet to level 5',             '🐶', 'pet',    5,    75),
    ('click_1k',  'Clicker',         'Earn 1,000 bits in Clicker',          '🖱️', 'bits',   1000, 10),
    ('click_100k','Click addict',    'Earn 100,000 bits in Clicker',        '🚀', 'bits',   100000, 75),
    ('req_1',     'Game scout',      'Request a game',                      '🎮', 'reqs',   1,    10)
  ) as t(key, title, descr, icon, stat, goal, reward);
$$;
revoke all on function public.hbu_ach_list() from public, anon, authenticated;

grant execute on function
  public.hbu_pet_get(text, text), public.hbu_pet_adopt(text, text, text, text), public.hbu_pet_feed(text, text),
  public.hbu_pet_play(text, text), public.hbu_pet_rename(text, text, text),
  public.hbu_clicker(text, text, integer, text, boolean),
  public.hbu_requests_get(text, text), public.hbu_request_post(text, text, text, text), public.hbu_request_vote(text, text, bigint),
  public.hbu_request_set(text, text, bigint, text), public.hbu_request_delete(text, text, bigint),
  public.hbu_achievements(text, text)
to anon, authenticated;
notify pgrst, 'reload schema';
