-- Chat polls (/poll and /endpoll). Run once in the Supabase SQL editor, then redeploy send-message.
-- Safe to run again.

create table if not exists public.polls (
  id bigint generated always as identity primary key,
  question text not null,
  options text[] not null,
  created_by text not null,
  created_at timestamptz not null default now(),
  closed boolean not null default false
);
create table if not exists public.poll_votes (
  poll_id bigint not null references public.polls(id) on delete cascade,
  username text not null,
  option_index integer not null,
  primary key (poll_id, username)
);
alter table public.polls enable row level security;
alter table public.poll_votes enable row level security;
revoke all on public.polls, public.poll_votes from anon, authenticated;

-- A poll stays open for 10 minutes unless a moderator ends it. Returns null when none is open.
create or replace function public.hbu_poll_get(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; p polls%rowtype; counts jsonb; mine int;
begin
  who := public.hbu_login(p_username, p_password);
  select * into p from polls
   where not closed and created_at > now() - interval '10 minutes'
   order by id desc limit 1;
  if not found then return null; end if;
  select coalesce(jsonb_agg(coalesce(c.n, 0) order by g.i), '[]'::jsonb) into counts
    from generate_series(0, array_length(p.options, 1) - 1) g(i)
    left join (select option_index, count(*) n from poll_votes where poll_id = p.id group by option_index) c
      on c.option_index = g.i;
  select option_index into mine from poll_votes where poll_id = p.id and username = who;
  return jsonb_build_object(
    'id', p.id, 'question', p.question, 'options', to_jsonb(p.options), 'by', p.created_by,
    'ends_at', p.created_at + interval '10 minutes', 'votes', counts, 'mine', mine);
end;
$$;

create or replace function public.hbu_poll_vote(p_username text, p_password text, p_poll bigint, p_option integer)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; p polls%rowtype;
begin
  who := public.hbu_login(p_username, p_password);
  select * into p from polls where id = p_poll and not closed and created_at > now() - interval '10 minutes';
  if not found then raise exception 'This poll has ended.'; end if;
  if p_option < 0 or p_option >= array_length(p.options, 1) then raise exception 'Invalid choice.'; end if;
  insert into poll_votes (poll_id, username, option_index) values (p_poll, who, p_option)
  on conflict (poll_id, username) do update set option_index = excluded.option_index;
end;
$$;

grant execute on function public.hbu_poll_get(text, text), public.hbu_poll_vote(text, text, bigint, integer) to anon, authenticated;
notify pgrst, 'reload schema';
