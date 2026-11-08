-- Run once in the Supabase SQL editor to make Student ID optional for signup.
-- Existing account data is left unchanged.

create or replace function public.hbu_signup(
  p_username text,
  p_password text,
  p_student_id text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_username !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'Username must be 3-20 letters, numbers or underscores';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if length(coalesce(trim(p_student_id), '')) > 30 then
    raise exception 'Student ID must be 30 characters or fewer';
  end if;
  if lower(p_username) = 'everyone' then
    raise exception 'That username is reserved';
  end if;
  if exists (select 1 from public.accounts where lower(username) = lower(p_username)) then
    raise exception 'That username is taken';
  end if;
  insert into public.accounts (username, password, student_id)
  values (p_username, crypt(p_password, gen_salt('bf')), nullif(trim(p_student_id), ''));
end;
$$;

notify pgrst, 'reload schema';
