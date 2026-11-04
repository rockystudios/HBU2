-- Adds a staff role labelled "Admin" with the ♔ badge (same commands as Moderator; edit them in the Owner app).
-- Its internal name is "administrator" because "admin" is the built-in Owner (Rocky).
-- Run once in the Supabase SQL editor. Safe to run again. No Edge Function change needed.
insert into public.custom_roles (name, label, badge, staff, commands) values
  ('administrator', 'Admin', '♔', true, array[
    'warn','ban','unban','mute','unmute','kick','clear','purge','announce','lock','unlock','slowmode',
    'botban','botunban','banlist','mutelist','whois','warns','addword','delword','words',
    'staff','me','shrug','tableflip','unflip','roll','flip','8ball','hug','highfive'])
on conflict (name) do nothing;
notify pgrst, 'reload schema';
