-- Update logs. Run once in the Supabase SQL editor. Safe to run again. No Edge Function change.
create table if not exists public.update_logs (
  id bigint generated always as identity primary key,
  title text not null,
  body text not null default '',
  created_at timestamptz not null default now()
);
alter table public.update_logs enable row level security;

-- Everyone can read the logs (no login needed).
create or replace function public.hbu_logs_get() returns table (id bigint, title text, body text, created_at timestamptz)
language sql security definer set search_path = public as $$
  select l.id, l.title, l.body, l.created_at from update_logs l order by l.created_at desc, l.id desc limit 100;
$$;

-- Only rocky can add or remove logs.
create or replace function public.hbu_log_add(p_username text, p_password text, p_title text, p_body text)
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare who text; t text := trim(coalesce(p_title, '')); b text := trim(coalesce(p_body, '')); new_id bigint;
begin
  who := public.hbu_login(p_username, p_password);
  if lower(who) <> 'rocky' then raise exception 'Only the owner can add logs.'; end if;
  if length(t) < 1 or length(t) > 80 then raise exception 'Give the log a title (up to 80 characters).'; end if;
  if length(b) > 2000 then raise exception 'That log is too long (2000 characters max).'; end if;
  insert into update_logs (title, body) values (t, b) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.hbu_log_delete(p_username text, p_password text, p_id bigint)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text;
begin
  who := public.hbu_login(p_username, p_password);
  if lower(who) <> 'rocky' then raise exception 'Only the owner can remove logs.'; end if;
  delete from update_logs where id = p_id;
end;
$$;

grant execute on function public.hbu_logs_get(), public.hbu_log_add(text, text, text, text), public.hbu_log_delete(text, text, bigint) to anon, authenticated;
notify pgrst, 'reload schema';
