-- Settings: blocking users and changing your username.
-- Run once in the Supabase SQL editor. No Edge Function change is needed.

alter table public.accounts add column if not exists blocked_users text[] not null default '{}';

create or replace function public.hbu_get_blocked(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; list text[];
begin
  who := public.hbu_login(p_username, p_password);
  select blocked_users into list from accounts where username = who;
  return to_jsonb(coalesce(list, '{}'));
end;
$$;

create or replace function public.hbu_set_block(p_username text, p_password text, p_target text, p_block boolean)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; real_target text; list text[];
begin
  who := public.hbu_login(p_username, p_password);
  select username into real_target from accounts where lower(username) = lower(trim(p_target));
  if real_target is null then raise exception 'No user with that name'; end if;
  if lower(real_target) = lower(who) then raise exception 'You cannot block yourself'; end if;
  if p_block then
    update accounts set blocked_users = array_append(array_remove(blocked_users, lower(real_target)), lower(real_target))
     where username = who returning blocked_users into list;
  else
    update accounts set blocked_users = array_remove(blocked_users, lower(real_target))
     where username = who returning blocked_users into list;
  end if;
  return to_jsonb(list);
end;
$$;

-- Changing your name needs your current password. History follows your new name.
create or replace function public.hbu_rename(p_username text, p_password text, p_new text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare who text; new_name text := trim(p_new);
begin
  who := public.hbu_login(p_username, p_password);
  if lower(who) = 'rocky' then raise exception 'The admin account cannot be renamed'; end if;
  if new_name !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'Username must be 3-20 letters, numbers or underscores';
  end if;
  if lower(new_name) in ('everyone', 'mod-bot', 'modbot', 'rocky', 'admin') then
    raise exception 'That username is reserved';
  end if;
  if new_name = who then raise exception 'That is already your username'; end if;
  if exists (select 1 from accounts where lower(username) = lower(new_name) and lower(username) <> lower(who)) then
    raise exception 'That username is taken';
  end if;

  update accounts set username = new_name where username = who;
  update messages set "user" = new_name where "user" = who;
  update messages set receiver = new_name where receiver = who;
  update mod_log set username = new_name where username = who;
  update mod_log set receiver = new_name where receiver = who;
  update accounts set blocked_users = array_replace(blocked_users, lower(who), lower(new_name))
   where lower(who) = any(blocked_users);
  return new_name;
end;
$$;

grant execute on function
  public.hbu_get_blocked(text, text),
  public.hbu_set_block(text, text, text, boolean),
  public.hbu_rename(text, text, text)
to anon, authenticated;

notify pgrst, 'reload schema';
