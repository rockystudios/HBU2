-- Owner password resets. Run once in the Supabase SQL editor (after accounts-and-dms.sql).
-- Rocky (owner app) allows a reset for a username. The next time someone tries to log in
-- with that username, the site lets them pick a new password. A reset works once and
-- expires after 48 hours. No Edge Function change is needed.

create table if not exists public.password_resets (
  username text primary key,
  requested_at timestamptz not null default now()
);
alter table public.password_resets enable row level security;
revoke all on public.password_resets from anon, authenticated;

create or replace function public.hbu_owner_check(p_username text, p_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text;
begin
  who := public.hbu_login(p_username, p_password);
  if lower(who) <> 'rocky' then raise exception 'Owner only'; end if;
end;
$$;

create or replace function public.hbu_owner_resets(p_username text, p_password text)
returns table (username text, requested_at timestamptz, expires_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.hbu_owner_check(p_username, p_password);
  delete from password_resets r where r.requested_at < now() - interval '48 hours';
  return query
    select r.username, r.requested_at, r.requested_at + interval '48 hours'
      from password_resets r order by r.requested_at desc;
end;
$$;

create or replace function public.hbu_owner_allow_reset(p_username text, p_password text, p_target text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare real_name text;
begin
  perform public.hbu_owner_check(p_username, p_password);
  select username into real_name from accounts where lower(username) = lower(trim(p_target));
  if real_name is null then raise exception 'No account called %', trim(p_target); end if;
  if lower(real_name) = 'rocky' then raise exception 'The owner account cannot be reset this way'; end if;
  insert into password_resets (username, requested_at) values (lower(real_name), now())
  on conflict (username) do update set requested_at = now();
  return real_name;
end;
$$;

create or replace function public.hbu_owner_cancel_reset(p_username text, p_password text, p_target text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.hbu_owner_check(p_username, p_password);
  delete from password_resets where username = lower(trim(p_target));
end;
$$;

-- Public: does this username have an open reset? (the login screen asks before checking a password)
create or replace function public.hbu_reset_pending(p_username text)
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from password_resets
     where username = lower(trim(p_username)) and requested_at > now() - interval '48 hours'
  );
$$;

-- Public: set a new password, but only while the owner has allowed a reset for that username.
create or replace function public.hbu_reset_password(p_username text, p_new text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare real_name text;
begin
  if length(coalesce(p_new, '')) < 6 then raise exception 'Password must be at least 6 characters'; end if;
  if not public.hbu_reset_pending(p_username) then
    raise exception 'No password reset is open for that username';
  end if;
  update accounts set password = crypt(p_new, gen_salt('bf'))
   where lower(username) = lower(trim(p_username)) and lower(username) <> 'rocky'
  returning username into real_name;
  if real_name is null then raise exception 'No password reset is open for that username'; end if;
  delete from password_resets where username = lower(trim(p_username));
  return real_name;
end;
$$;

grant execute on function
  public.hbu_owner_resets(text, text),
  public.hbu_owner_allow_reset(text, text, text),
  public.hbu_owner_cancel_reset(text, text, text),
  public.hbu_reset_pending(text),
  public.hbu_reset_password(text, text)
to anon, authenticated;
revoke execute on function public.hbu_owner_check(text, text) from anon, authenticated;

notify pgrst, 'reload schema';
