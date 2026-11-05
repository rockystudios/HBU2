-- Change your own password from Settings. Run once in the Supabase SQL editor. Safe to run again. No Edge Function change.
-- Passwords are checked on every request, so changing it signs out every other open browser automatically.
create or replace function public.hbu_change_password(p_username text, p_password text, p_new text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text;
begin
  who := public.hbu_login(p_username, p_password);
  if length(coalesce(p_new, '')) < 6 or length(p_new) > 100 then raise exception 'Password must be at least 6 characters'; end if;
  if p_new = p_password then raise exception 'Pick a different password than your old one'; end if;
  update accounts set password = crypt(p_new, gen_salt('bf')) where username = who;
end;
$$;
grant execute on function public.hbu_change_password(text, text, text) to anon, authenticated;
notify pgrst, 'reload schema';
