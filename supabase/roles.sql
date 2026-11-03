-- Roles and mutes. Run once in the Supabase SQL editor, then redeploy send-message.
-- accounts.role is NULL (no role), 'mod' or 'vip'. The admin (rocky) is set on the server.
--   mod: /ban /warn /mute /unmute, delete messages, manage filters
--   vip: /warn and /sugban only

alter table public.accounts add column if not exists role text;
alter table public.accounts add column if not exists muted_until timestamptz;
alter table public.accounts drop constraint if exists accounts_role_check;
alter table public.accounts add constraint accounts_role_check check (role in ('mod', 'vip'));

-- Carry existing moderators over from the old is_mod column (kept, but no longer used).
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'accounts' and column_name = 'is_mod') then
    execute 'update public.accounts set role = ''mod'' where is_mod = true and role is null';
  end if;
end $$;

create or replace function public.hbu_roles()
returns table (username text, role text)
language sql security definer set search_path = public as $$
  select a.username, a.role from accounts a where a.role is not null;
$$;

-- Older site versions still call this one.
create or replace function public.hbu_mod_names()
returns table (username text)
language sql security definer set search_path = public as $$
  select a.username from accounts a where a.role = 'mod';
$$;

grant execute on function public.hbu_roles(), public.hbu_mod_names() to anon, authenticated;

notify pgrst, 'reload schema';

-- Handy admin commands:
--   Give a role:  update accounts set role = 'vip' where lower(username) = 'someone';
--   Remove it:    update accounts set role = null  where lower(username) = 'someone';
