-- Profile pictures. Run once in the Supabase SQL editor. No Edge Function change is needed.
-- An avatar is either a small image (a data: URL made by the site, about 96x96)
-- or a single emoji.

alter table public.accounts add column if not exists avatar text;

create or replace function public.hbu_set_avatar(p_username text, p_password text, p_avatar text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare who text; val text := nullif(trim(coalesce(p_avatar, '')), '');
begin
  who := public.hbu_login(p_username, p_password);
  if val is not null then
    if val like 'data:image/%;base64,%' then
      if length(val) > 30000 then raise exception 'That picture is too big'; end if;
      if val !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' then raise exception 'Unsupported picture'; end if;
    elsif char_length(val) > 8 or val ~ '[<>"''/\\]' then
      raise exception 'Invalid avatar';
    end if;
  end if;
  update accounts set avatar = val where username = who;
  return val;
end;
$$;

create or replace function public.hbu_avatars()
returns table (username text, avatar text)
language sql security definer set search_path = public as $$
  select a.username, a.avatar from accounts a where a.avatar is not null;
$$;

grant execute on function public.hbu_set_avatar(text, text, text), public.hbu_avatars() to anon, authenticated;

notify pgrst, 'reload schema';
