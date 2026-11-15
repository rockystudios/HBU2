-- Improved HBU Casino odds and daily streak rewards.
-- Run after supabase/coins.sql, supabase/streaks-ips.sql, and supabase/gambling.sql.

create or replace function public.hbu_wallet(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  who text;
  a accounts%rowtype;
  today date := (now() at time zone 'utc')::date;
begin
  who := public.hbu_login(p_username, p_password);
  select * into a from public.accounts where username = who;
  return jsonb_build_object(
    'coins', a.coins,
    'owned', to_jsonb(a.owned_plates),
    'active', a.active_plate,
    'can_spin', a.last_spin is null or a.last_spin < today,
    'next_spin', ((today + 1)::timestamp at time zone 'utc'),
    'streak', case when a.last_spin is not null and a.last_spin >= today - 1 then a.streak else 0 end,
    'best_streak', a.best_streak
  );
end;
$$;

create or replace function public.hbu_spin(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  who text;
  today date := (now() at time zone 'utc')::date;
  roll int := floor(random() * 100)::int;
  prize int;
  bonus int;
  total int;
  prev date;
  current_streak int;
  new_streak int;
  current_owned text[];
  reward_plate text;
  reward_name text;
  streak_reward text := null;
begin
  who := public.hbu_login(p_username, p_password);

  -- Better daily prize distribution: higher prizes are more common than before.
  prize := case
    when roll < 25 then 10
    when roll < 50 then 25
    when roll < 75 then 50
    when roll < 90 then 75
    when roll < 98 then 100
    else 250
  end;

  select last_spin, streak, owned_plates
    into prev, current_streak, current_owned
    from public.accounts
    where username = who
    for update;

  new_streak := case when prev = today - 1 then coalesce(current_streak, 0) + 1 else 1 end;

  -- Every consecutive day now grants extra coins, increasing through day 10.
  bonus := least(new_streak, 10) * 10;

  -- Every third day adds another milestone bonus.
  if new_streak % 3 = 0 then
    bonus := bonus + 50;
    streak_reward := '3-day streak milestone';
  end if;

  -- Every seventh day grants a random unowned name plate.
  if new_streak % 7 = 0 then
    select id, name
      into reward_plate, reward_name
      from public.plates
      where not (id = any(coalesce(current_owned, '{}'::text[])))
      order by random()
      limit 1;

    if reward_plate is not null then
      streak_reward := concat_ws(' · ', nullif(streak_reward, ''), 'Free name plate: ' || reward_name);
    else
      bonus := bonus + 250;
      streak_reward := concat_ws(' · ', nullif(streak_reward, ''), 'All name plates unlocked');
    end if;
  end if;

  update public.accounts
     set coins = coins + prize + bonus,
         last_spin = today,
         streak = new_streak,
         best_streak = greatest(best_streak, new_streak),
         owned_plates = case
           when reward_plate is not null then array_append(coalesce(owned_plates, '{}'::text[]), reward_plate)
           else owned_plates
         end
   where username = who
     and (last_spin is null or last_spin < today)
   returning coins into total;

  if total is null then
    raise exception 'You already spun today. Come back tomorrow!';
  end if;

  return jsonb_build_object(
    'prize', prize,
    'bonus', bonus,
    'streak', new_streak,
    'streak_reward', streak_reward,
    'free_plate', reward_plate,
    'coins', total
  );
end;
$$;

create or replace function public.hbu_gamble(
  p_username text,
  p_password text,
  p_game text,
  p_bet integer,
  p_pick text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  who text;
  have int;
  payout int := 0;
  total int;
  roll int;
  res jsonb;
  sym text[] := array['🍒','🍋','🔔','⭐','7️⃣'];
  r1 int;
  r2 int;
  r3 int;
begin
  who := public.hbu_login(p_username, p_password);
  if p_bet is null or p_bet < 1 or p_bet > 1000 then
    raise exception 'Bet between 1 and 1000 coins.';
  end if;

  select coins into have from public.accounts where username = who for update;
  if have < p_bet then raise exception 'Not enough coins.'; end if;

  if p_game = 'flip' then
    if coalesce(p_pick, '') not in ('heads', 'tails') then
      raise exception 'Pick heads or tails.';
    end if;
    roll := floor(random() * 100)::int;
    -- 52% chance to win, still pays 2x.
    if roll < 52 then
      payout := p_bet * 2;
      res := jsonb_build_object('side', p_pick);
    else
      res := jsonb_build_object('side', case when p_pick = 'heads' then 'tails' else 'heads' end);
    end if;
  elsif p_game = 'dice' then
    if coalesce(p_pick, '') not in ('high', 'low') then
      raise exception 'Pick high or low.';
    end if;
    roll := floor(random() * 100)::int + 1;
    -- Each choice wins on 52 of 100 outcomes; four middle values favor either pick.
    if (p_pick = 'low' and roll <= 52) or (p_pick = 'high' and roll >= 49) then
      payout := p_bet * 2;
    end if;
    res := jsonb_build_object('roll', roll);
  elsif p_game = 'slots' then
    -- Five symbols instead of six raises the chance of a matching payout to 48%.
    r1 := floor(random() * 5)::int + 1;
    r2 := floor(random() * 5)::int + 1;
    r3 := floor(random() * 5)::int + 1;
    if r1 = r2 and r2 = r3 then
      payout := p_bet * (case when r1 = 5 then 20 else 8 end);
    elsif r1 = r2 or r2 = r3 or r1 = r3 then
      payout := greatest(p_bet + 1, (p_bet * 5) / 4);
    end if;
    res := jsonb_build_object('reels', jsonb_build_array(sym[r1], sym[r2], sym[r3]));
  else
    raise exception 'Unknown game.';
  end if;

  update public.accounts
     set coins = coins - p_bet + payout
   where username = who
   returning coins into total;

  -- Counts toward quests when the optional quests migration is installed.
  begin
    perform public.hbu_quest_bump(who, 'casino', 1);
    if payout > p_bet then perform public.hbu_quest_bump(who, 'casino_win', 1); end if;
  exception when others then
    null;
  end;

  return res || jsonb_build_object(
    'payout', payout,
    'bet', p_bet,
    'coins', total,
    'won', payout > p_bet
  );
end;
$$;

revoke all on function public.hbu_wallet(text, text) from public;
revoke all on function public.hbu_spin(text, text) from public;
revoke all on function public.hbu_gamble(text, text, text, integer, text) from public;

grant execute on function public.hbu_wallet(text, text) to anon, authenticated;
grant execute on function public.hbu_spin(text, text) to anon, authenticated;
grant execute on function public.hbu_gamble(text, text, text, integer, text) to anon, authenticated;

notify pgrst, 'reload schema';
