-- Custom roles, editable from the Owner app. Run once in the Supabase SQL editor,
-- then redeploy send-message (Verify JWT off). Safe to run again.

create table if not exists public.custom_roles (
  name text primary key,
  label text not null,
  badge text not null default '★',
  staff boolean not null default false,   -- staff roles get the admin panel, protection from non-admins, and can talk while the chat is locked
  commands text[] not null default '{}'
);
alter table public.custom_roles enable row level security;
revoke all on public.custom_roles from anon, authenticated;

-- Any role name is allowed now (the old check only allowed mod and vip).
alter table public.accounts drop constraint if exists accounts_role_check;

insert into public.custom_roles (name, label, badge, staff, commands) values
  ('mod', 'Moderator', '✔', true, array[
    'warn','ban','unban','mute','unmute','kick','clear','purge','announce','lock','unlock','slowmode',
    'botban','botunban','banlist','mutelist','whois','warns','addword','delword','words',
    'staff','me','shrug','tableflip','unflip','roll','flip','8ball','hug','highfive']),
  ('vip', 'VIP', '★', false, array[
    'warn','sugban','staff','me','shrug','tableflip','unflip','roll','flip','8ball','hug','highfive']),
  ('dev', 'Dev', '</>', false, array[]::text[])
on conflict (name) do nothing;

-- The site reads role names and badges from here (no commands are exposed).
create or replace function public.hbu_role_defs()
returns table (name text, label text, badge text)
language sql security definer set search_path = public as $$
  select r.name, r.label, r.badge from custom_roles r;
$$;
grant execute on function public.hbu_role_defs() to anon, authenticated;

notify pgrst, 'reload schema';
