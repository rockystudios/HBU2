-- Shared "unblocked links" app. Run once in the Supabase SQL editor. No Edge Function change needed. Safe to run again.

create table if not exists public.shared_links (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  posted_by text not null,
  title text not null,
  url text not null,
  copies integer not null default 0
);
alter table public.shared_links enable row level security;
revoke all on public.shared_links from anon, authenticated;

-- Anyone can read the list (no login needed).
create or replace function public.hbu_links_get()
returns table (id bigint, created_at timestamptz, posted_by text, title text, url text, copies integer)
language sql security definer set search_path = public as $$
  select id, created_at, posted_by, title, url, copies from shared_links order by created_at desc limit 200;
$$;

create or replace function public.hbu_link_post(p_username text, p_password text, p_title text, p_url text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; u text := trim(coalesce(p_url, '')); t text := trim(coalesce(p_title, ''));
begin
  who := public.hbu_login(p_username, p_password);
  if length(t) < 2 or length(t) > 40 then raise exception 'Give it a name (2-40 characters).'; end if;
  if u !~* '^https?://[^\s/$.?#][^\s]*\.[^\s]{2,}$' or length(u) > 300 then raise exception 'That does not look like a valid link (start with https://).'; end if;
  if exists (select 1 from shared_links where lower(url) = lower(u)) then raise exception 'That link was already posted.'; end if;
  if (select count(*) from shared_links where lower(posted_by) = lower(who) and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'You can post 5 links per hour. Try again later.';
  end if;
  insert into shared_links (posted_by, title, url) values (who, t, u);
end;
$$;

-- Owners of a link, mods and the admin can remove it.
create or replace function public.hbu_link_delete(p_username text, p_password text, p_id bigint)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; r text; l shared_links%rowtype;
begin
  who := public.hbu_login(p_username, p_password);
  select * into l from shared_links where id = p_id;
  if l.id is null then return; end if;
  select role into r from accounts where username = who;
  if lower(l.posted_by) <> lower(who) and coalesce(r, '') <> 'mod' and lower(who) <> 'rocky' then
    raise exception 'You can only remove your own links.';
  end if;
  delete from shared_links where id = p_id;
end;
$$;

create or replace function public.hbu_link_copied(p_id bigint)
returns void language sql security definer set search_path = public as $$
  update shared_links set copies = copies + 1 where id = p_id;
$$;

grant execute on function public.hbu_links_get(), public.hbu_link_post(text, text, text, text),
  public.hbu_link_delete(text, text, bigint), public.hbu_link_copied(bigint) to anon, authenticated;
notify pgrst, 'reload schema';
