-- Add the Dev role to an existing role-editor setup without changing an existing role.
-- Run supabase/role-editor.sql first if custom roles are not set up.
insert into public.custom_roles (name, label, badge, staff, commands)
values ('dev', 'Dev', '</>', false, array[]::text[])
on conflict (name) do nothing;
