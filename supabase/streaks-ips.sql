-- Daily streaks and the owner's account/IP list. Run once in the Supabase SQL editor,
-- then redeploy send-message (Verify JWT off). Safe to run again.

-- Streaks: spin on consecutive UTC days. Day 2 gives +5 bonus coins, day 3 +10, ... up to +50.
alter table public.accounts add column if not exists streak integer not null default 0;
alter table public.accounts add column if not exists best_streak integer not null default 0;

-- IPs: send-message records the last IP each account used (only the owner can read them).
alter table public.accounts add column if not exists last_ip text;
alter table public.accounts add column if not exists last_seen timestamptz;

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
    'next_spin', ((today + 1)::timestamp at time zone 'utc'),
    -- A streak is only alive if you spun today or yesterday.
    'streak', case when a.last_spin is not null and a.last_spin >= today - 1 then a.streak else 0 end,
    'best_streak', a.best_streak
  );
end;
$$;

create or replace function public.hbu_spin(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  who text; today date := (now() at time zone 'utc')::date; roll int := floor(random() * 100)::int;
  prize int; bonus int; total int; prev date; new_streak int;
begin
  who := public.hbu_login(p_username, p_password);
  prize := case when roll < 35 then 10 when roll < 65 then 25 when roll < 83 then 50
                when roll < 93 then 75 when roll < 98 then 100 else 250 end;
  select last_spin, streak into prev, new_streak from accounts where username = who for update;
  new_streak := case when prev = today - 1 then new_streak + 1 else 1 end;
  bonus := least(new_streak - 1, 10) * 5;
  update accounts
     set coins = coins + prize + bonus, last_spin = today,
         streak = new_streak, best_streak = greatest(best_streak, new_streak)
   where username = who and (last_spin is null or last_spin < today)
   returning coins into total;
  if total is null then raise exception 'You already spun today. Come back tomorrow!'; end if;
  return jsonb_build_object('prize', prize, 'bonus', bonus, 'streak', new_streak, 'coins', total);
end;
$$;

notify pgrst, 'reload schema';
