-- "Someone is typing…" for the main chat. Run once in the Supabase SQL editor. No Edge Function change needed.

create table if not exists public.typing (
  username text primary key,
  at timestamptz not null default now()
);
alter table public.typing enable row level security;
revoke all on public.typing from anon, authenticated;

create or replace function public.hbu_typing_ping(p_username text, p_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text;
begin
  who := public.hbu_login(p_username, p_password);
  insert into typing (username, at) values (who, now())
  on conflict (username) do update set at = now();
end;
$$;

create or replace function public.hbu_typing_who(p_username text, p_password text)
returns table (username text)
language plpgsql security definer set search_path = public, extensions as $$
declare who text;
begin
  who := public.hbu_login(p_username, p_password);
  return query select t.username from typing t where t.at > now() - interval '4 seconds' and t.username <> who order by t.at desc limit 5;
end;
$$;

grant execute on function public.hbu_typing_ping(text, text), public.hbu_typing_who(text, text) to anon, authenticated;
notify pgrst, 'reload schema';
