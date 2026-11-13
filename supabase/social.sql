-- HBU Social: text and image posts, likes and followers.
-- Run once in the Supabase SQL editor. Safe to run again. No Edge Function change.
create table if not exists public.social_posts (
  id bigint generated always as identity primary key,
  author text not null,
  body text not null default '',
  image text,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists social_posts_author_idx on public.social_posts (lower(author), id desc);
create table if not exists public.social_likes (
  post_id bigint not null references public.social_posts(id) on delete cascade,
  username text not null,
  primary key (post_id, username)
);
create table if not exists public.social_comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.social_posts(id) on delete cascade,
  author text not null,
  body text not null check (char_length(body) between 1 and 300),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists social_comments_post_idx on public.social_comments(post_id, id);

create table if not exists public.social_follows (
  follower text not null,
  followee text not null,
  created_at timestamptz not null default now(),
  primary key (follower, followee),
  check (lower(follower) <> lower(followee))
);
alter table public.social_posts enable row level security;
alter table public.social_likes enable row level security;
alter table public.social_comments enable row level security;
alter table public.social_follows enable row level security;

create or replace function public.hbu_social_staff(who text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare r text; s boolean := false;
begin
  if lower(who) = 'rocky' then return true; end if;
  select role into r from accounts where username = who;
  begin
    select coalesce(bool_or(c.staff), false) into s from custom_roles c where c.name = r;
  exception when undefined_table then s := false;
  end;
  return s;
end;
$$;
revoke all on function public.hbu_social_staff(text) from public, anon, authenticated;

-- Feed. p_mode: 'all', 'following' (people you follow plus you) or 'user' (one person's posts).
create or replace function public.hbu_social_feed(p_username text, p_password text, p_mode text default 'all', p_user text default null, p_before bigint default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; staff boolean; rows jsonb;
begin
  who := public.hbu_login(p_username, p_password);
  staff := public.hbu_social_staff(who);
  select coalesce(jsonb_agg(x order by (x->>'id')::bigint desc), '[]'::jsonb) into rows from (
    select jsonb_build_object(
      'id', p.id, 'author', p.author, 'body', p.body, 'image', p.image, 'created_at', p.created_at,
      'likes', (select count(*) from social_likes l where l.post_id = p.id),
      'comments', (select count(*) from social_comments c where c.post_id = p.id and c.deleted_at is null),
      'liked', exists (select 1 from social_likes l where l.post_id = p.id and l.username = who),
      'mine', lower(p.author) = lower(who),
      'can_delete', staff or lower(p.author) = lower(who),
      'following', exists (select 1 from social_follows f where f.follower = who and lower(f.followee) = lower(p.author))
    ) as x
    from social_posts p
    where p.deleted_at is null
      and (p_before is null or p.id < p_before)
      and (
        coalesce(p_mode, 'all') = 'all'
        or (p_mode = 'following' and (lower(p.author) = lower(who) or exists (select 1 from social_follows f where f.follower = who and lower(f.followee) = lower(p.author))))
        or (p_mode = 'user' and lower(p.author) = lower(coalesce(p_user, '')))
      )
    order by p.id desc
    limit 15
  ) t;
  return rows;
end;
$$;

create or replace function public.hbu_social_post(p_username text, p_password text, p_body text, p_image text default null)
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare who text; b text := trim(coalesce(p_body, '')); new_id bigint;
begin
  who := public.hbu_login(p_username, p_password);
  if length(b) > 500 then raise exception 'Posts can be up to 500 characters.'; end if;
  if p_image is not null and p_image <> '' then
    if p_image !~ '^data:image/(png|webp|jpeg);base64,' or length(p_image) > 200000 then raise exception 'Only small png, jpeg or webp images are allowed (no videos or gifs).'; end if;
  else
    p_image := null;
  end if;
  if b = '' and p_image is null then raise exception 'Write something or add a picture.'; end if;
  begin
    if exists (select 1 from banned_words w where lower(b) like '%' || lower(w.word) || '%') then raise exception 'That post has a word that is not allowed.'; end if;
  exception when undefined_table then null;
  end;
  if exists (select 1 from social_posts where lower(author) = lower(who) and created_at > now() - interval '15 seconds') then raise exception 'Slow down a little before posting again.'; end if;
  if (select count(*) from social_posts where lower(author) = lower(who) and created_at > now() - interval '1 day' and deleted_at is null) >= 30 then raise exception 'That is the limit of 30 posts a day.'; end if;
  insert into social_posts (author, body, image) values (who, b, p_image) returning id into new_id;
  return new_id;
end;
$$;

-- Like or unlike. Returns the new like count and whether you like it now.
create or replace function public.hbu_social_like(p_username text, p_password text, p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; liked boolean;
begin
  who := public.hbu_login(p_username, p_password);
  if not exists (select 1 from social_posts where id = p_id and deleted_at is null) then raise exception 'That post is gone.'; end if;
  delete from social_likes where post_id = p_id and username = who;
  if not found then
    insert into social_likes (post_id, username) values (p_id, who);
    liked := true;
  else
    liked := false;
  end if;
  return jsonb_build_object('liked', liked, 'likes', (select count(*) from social_likes where post_id = p_id));
end;
$$;

create or replace function public.hbu_social_follow(p_username text, p_password text, p_target text, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; t text;
begin
  who := public.hbu_login(p_username, p_password);
  select username into t from accounts where lower(username) = lower(trim(coalesce(p_target, '')));
  if t is null then raise exception 'That user does not exist.'; end if;
  if lower(t) = lower(who) then raise exception 'You cannot follow yourself.'; end if;
  if p_on then
    insert into social_follows (follower, followee) values (who, t) on conflict do nothing;
  else
    delete from social_follows where follower = who and lower(followee) = lower(t);
  end if;
  return jsonb_build_object('following', p_on, 'followers', (select count(*) from social_follows where lower(followee) = lower(t)));
end;
$$;

create or replace function public.hbu_social_profile(p_username text, p_password text, p_target text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; t text;
begin
  who := public.hbu_login(p_username, p_password);
  select username into t from accounts where lower(username) = lower(trim(coalesce(p_target, '')));
  if t is null then raise exception 'That user does not exist.'; end if;
  return jsonb_build_object(
    'username', t,
    'me', lower(t) = lower(who),
    'followers', (select count(*) from social_follows where lower(followee) = lower(t)),
    'following', (select count(*) from social_follows where lower(follower) = lower(t)),
    'posts', (select count(*) from social_posts where lower(author) = lower(t) and deleted_at is null),
    'followed', exists (select 1 from social_follows where follower = who and lower(followee) = lower(t))
  );
end;
$$;

-- Authors delete their own posts; staff (and Rocky) can delete anyone's. Posts are hidden, not erased.
create or replace function public.hbu_social_delete(p_username text, p_password text, p_id bigint)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; a text;
begin
  who := public.hbu_login(p_username, p_password);
  select author into a from social_posts where id = p_id and deleted_at is null;
  if a is null then return; end if;
  if lower(a) <> lower(who) and not public.hbu_social_staff(who) then raise exception 'You can only delete your own posts.'; end if;
  update social_posts set deleted_at = now() where id = p_id;
end;
$$;


-- Comments on posts. All reads/writes go through password-authenticated RPCs.
create or replace function public.hbu_social_comments(p_username text, p_password text, p_post_id bigint)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; rows jsonb;
begin
  who := public.hbu_login(p_username, p_password);
  if not exists (select 1 from social_posts where id = p_post_id and deleted_at is null) then
    raise exception 'That post is gone.';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'author', c.author, 'body', c.body, 'created_at', c.created_at,
    'mine', lower(c.author) = lower(who),
    'can_delete', lower(c.author) = lower(who) or public.hbu_social_staff(who)
  ) order by c.id asc), '[]'::jsonb)
  into rows from social_comments c
  where c.post_id = p_post_id and c.deleted_at is null;
  return rows;
end;
$$;

create or replace function public.hbu_social_comment(p_username text, p_password text, p_post_id bigint, p_body text)
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare who text; b text := trim(coalesce(p_body, '')); new_id bigint;
begin
  who := public.hbu_login(p_username, p_password);
  if not exists (select 1 from social_posts where id = p_post_id and deleted_at is null) then raise exception 'That post is gone.'; end if;
  if b = '' or length(b) > 300 then raise exception 'Comments must be 1-300 characters.'; end if;
  if exists (select 1 from social_comments where lower(author) = lower(who) and created_at > now() - interval '5 seconds') then raise exception 'Wait a few seconds before commenting again.'; end if;
  if (select count(*) from social_comments where lower(author) = lower(who) and created_at > now() - interval '1 day' and deleted_at is null) >= 60 then raise exception 'That is the limit of 60 comments a day.'; end if;
  begin
    if exists (select 1 from banned_words w where lower(b) like '%' || lower(w.word) || '%') then raise exception 'That comment has a word that is not allowed.'; end if;
  exception when undefined_table then null;
  end;
  insert into social_comments(post_id, author, body) values (p_post_id, who, b) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.hbu_social_comment_delete(p_username text, p_password text, p_id bigint)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare who text; a text;
begin
  who := public.hbu_login(p_username, p_password);
  select author into a from social_comments where id = p_id and deleted_at is null;
  if a is null then return; end if;
  if lower(a) <> lower(who) and not public.hbu_social_staff(who) then raise exception 'You can only delete your own comments.'; end if;
  update social_comments set deleted_at = now() where id = p_id;
end;
$$;

grant execute on function
  public.hbu_social_feed(text, text, text, text, bigint),
  public.hbu_social_post(text, text, text, text),
  public.hbu_social_like(text, text, bigint),
  public.hbu_social_follow(text, text, text, boolean),
  public.hbu_social_profile(text, text, text),
  public.hbu_social_delete(text, text, bigint),
  public.hbu_social_comments(text, text, bigint),
  public.hbu_social_comment(text, text, bigint, text),
  public.hbu_social_comment_delete(text, text, bigint)
to anon, authenticated;
notify pgrst, 'reload schema';
