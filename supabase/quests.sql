-- Daily and weekly quests that pay coins. Run once in the Supabase SQL editor, THEN run supabase/gambling.sql again
-- (it now counts casino rounds). No Edge Function change needed. Safe to run again.

create table if not exists public.quests (
  id text primary key,
  title text not null,
  event text not null,           -- message | spin | casino | casino_win | poll | arcade | streak
  goal integer not null check (goal > 0),
  reward integer not null check (reward > 0),
  period text not null check (period in ('daily', 'weekly')),
  sort integer not null default 0,
  active boolean not null default true
);
create table if not exists public.quest_progress (
  username text not null,
  quest_id text not null references public.quests(id) on delete cascade,
  period_start date not null,
  progress integer not null default 0,
  claimed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (username, quest_id, period_start)
);
alter table public.quests enable row level security;
alter table public.quest_progress enable row level security;
revoke all on public.quests, public.quest_progress from anon, authenticated;

insert into public.quests (id, title, event, goal, reward, period, sort) values
  ('d_msg',    'Send 5 messages in the main chat',  'message',    5,  20, 'daily',  1),
  ('d_spin',   'Spin the daily wheel',               'spin',       1,  15, 'daily',  2),
  ('d_casino', 'Play 3 casino rounds',               'casino',     3,  25, 'daily',  3),
  ('d_poll',   'Vote in a poll',                     'poll',       1,  20, 'daily',  4),
  ('d_arcade', 'Play an arcade game',                'arcade',     1,  15, 'daily',  5),
  ('w_msg',    'Send 50 messages in the main chat', 'message',    50, 150, 'weekly', 1),
  ('w_streak', 'Reach a 5-day spin streak',          'streak',     5, 250, 'weekly', 2),
  ('w_arcade', 'Play 10 arcade games',               'arcade',     10, 200, 'weekly', 3),
  ('w_win',    'Win 5 casino rounds',                'casino_win', 5, 300, 'weekly', 4)
on conflict (id) do nothing;

create or replace function public.hbu_quest_period(p_period text)
returns date language sql immutable as $$
  select case when p_period = 'weekly' then date_trunc('week', (now() at time zone 'utc'))::date
              else (now() at time zone 'utc')::date end;
$$;

-- Server-only: counts progress for every active quest listening to p_event.
create or replace function public.hbu_quest_bump(p_username text, p_event text, p_amount integer default 1)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare q quests%rowtype;
begin
  for q in select * from quests where event = p_event and active loop
    insert into quest_progress (username, quest_id, period_start, progress)
    values (p_username, q.id, public.hbu_quest_period(q.period), least(q.goal, p_amount))
    on conflict (username, quest_id, period_start)
    do update set progress = least(q.goal, quest_progress.progress + p_amount), updated_at = now();
  end loop;
end;
$$;
revoke all on function public.hbu_quest_bump(text, text, integer) from public, anon, authenticated;

-- Triggers so no Edge Function change is needed. They never block the real action.
create or replace function public.hbu_quest_trg_message() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.receiver = 'everyone' and new."user" <> 'mod-bot' then perform public.hbu_quest_bump(new."user", 'message', 1); end if;
  return new;
exception when others then return new;
end;
$$;
drop trigger if exists hbu_quest_message on public.messages;
create trigger hbu_quest_message after insert on public.messages for each row execute function public.hbu_quest_trg_message();

create or replace function public.hbu_quest_trg_spin() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.last_spin is distinct from old.last_spin then perform public.hbu_quest_bump(new.username, 'spin', 1); end if;
  return new;
exception when others then return new;
end;
$$;
drop trigger if exists hbu_quest_spin on public.accounts;
create trigger hbu_quest_spin after update of last_spin on public.accounts for each row execute function public.hbu_quest_trg_spin();

create or replace function public.hbu_quest_trg_poll() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.hbu_quest_bump(new.username, 'poll', 1);
  return new;
exception when others then return new;
end;
$$;
drop trigger if exists hbu_quest_poll on public.poll_votes;
create trigger hbu_quest_poll after insert on public.poll_votes for each row execute function public.hbu_quest_trg_poll();

-- Arcade plays are reported by the browser, so they count at most once per minute per account.
create or replace function public.hbu_quest_play(p_username text, p_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; last_at timestamptz;
begin
  who := public.hbu_login(p_username, p_password);
  select max(updated_at) into last_at from quest_progress qp join quests q on q.id = qp.quest_id
   where qp.username = who and q.event = 'arcade';
  if last_at is null or last_at < now() - interval '60 seconds' then
    perform public.hbu_quest_bump(who, 'arcade', 1);
  end if;
end;
$$;

create or replace function public.hbu_quests_get(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; a accounts%rowtype; today date := (now() at time zone 'utc')::date; live int;
begin
  who := public.hbu_login(p_username, p_password);
  select * into a from accounts where username = who;
  live := case when a.last_spin is not null and a.last_spin >= today - 1 then a.streak else 0 end;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', q.id, 'title', q.title, 'period', q.period, 'goal', q.goal, 'reward', q.reward,
      'progress', case when q.event = 'streak' then least(q.goal, live) else least(q.goal, coalesce(p.progress, 0)) end,
      'claimed', coalesce(p.claimed, false),
      'ends_at', case when q.period = 'weekly' then ((public.hbu_quest_period('weekly') + 7)::timestamp at time zone 'utc')
                      else ((today + 1)::timestamp at time zone 'utc') end
    ) order by q.period desc, q.sort)
    from quests q
    left join quest_progress p on p.quest_id = q.id and p.username = who and p.period_start = public.hbu_quest_period(q.period)
    where q.active), '[]'::jsonb);
end;
$$;

create or replace function public.hbu_quest_claim(p_username text, p_password text, p_quest text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; q quests%rowtype; a accounts%rowtype; today date := (now() at time zone 'utc')::date; prog int; total int; ps date;
begin
  who := public.hbu_login(p_username, p_password);
  select * into q from quests where id = p_quest and active;
  if q.id is null then raise exception 'That quest does not exist.'; end if;
  ps := public.hbu_quest_period(q.period);
  insert into quest_progress (username, quest_id, period_start, progress) values (who, q.id, ps, 0)
  on conflict do nothing;
  select progress into prog from quest_progress where username = who and quest_id = q.id and period_start = ps for update;
  if q.event = 'streak' then
    select * into a from accounts where username = who;
    prog := case when a.last_spin is not null and a.last_spin >= today - 1 then a.streak else 0 end;
  end if;
  if prog < q.goal then raise exception 'Quest not finished yet.'; end if;
  update quest_progress set claimed = true where username = who and quest_id = q.id and period_start = ps and not claimed;
  if not found then raise exception 'Already claimed.'; end if;
  update accounts set coins = coins + q.reward where username = who returning coins into total;
  return jsonb_build_object('reward', q.reward, 'coins', total);
end;
$$;

grant execute on function public.hbu_quest_play(text, text), public.hbu_quests_get(text, text), public.hbu_quest_claim(text, text, text) to anon, authenticated;
notify pgrst, 'reload schema';
