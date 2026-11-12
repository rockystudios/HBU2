-- Deletes every account whose student ID contains "STFU" (any capitals), plus their messages.
-- Skips rocky and any owner. Run STEP 1 first to preview, then STEP 2 to delete.

-- STEP 1: preview
select username, student_id, role
from public.accounts
where student_id ilike '%STFU%'
  and lower(username) <> 'rocky'
  and coalesce(role, '') <> 'owner';

-- STEP 2: delete (select and run only this part)
delete from public.messages
where "user" in (
  select username from public.accounts
  where student_id ilike '%STFU%'
    and lower(username) <> 'rocky'
    and coalesce(role, '') <> 'owner'
);

delete from public.accounts
where student_id ilike '%STFU%'
  and lower(username) <> 'rocky'
  and coalesce(role, '') <> 'owner';
