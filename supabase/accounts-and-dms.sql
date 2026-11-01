-- Run once in the Supabase SQL editor (Dashboard -> SQL Editor).
-- Accounts and DMs go through server-side functions so passwords are hashed
-- and the public (anon) key can never read accounts or other people's DMs.

create extension if not exists pgcrypto with schema extensions;

-- accounts: username, password, student_id
alter table public.accounts add column if not exists student_id text;
alter table public.accounts alter column student_id type text using student_id::text;
create unique index if not exists accounts_username_key on public.accounts (lower(username));

-- Hash any passwords that are still plain text (bcrypt hashes start with $2).
update public.accounts
   set password = extensions.crypt(password, extensions.gen_salt('bf'))
 where password not like '$2%';

-- messages: receiver defaults to 'everyone' (the main chat)
alter table public.messages add column if not exists receiver text not null default 'everyone';

-- Lock tables down: the public key can only read the main chat.
alter table public.accounts enable row level security;
alter table public.messages enable row level security;
drop policy if exists "public read" on public.messages;
drop policy if exists "public insert" on public.messages;
drop policy if exists "read main chat" on public.messages;
create policy "read main chat" on public.messages for select using (receiver = 'everyone');
revoke all on public.accounts from anon, authenticated;
revoke insert, update, delete on public.messages from anon, authenticated;

create or replace function public.hbu_signup(p_username text, p_password text, p_student_id text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_username !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'Username must be 3-20 letters, numbers or underscores';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if length(coalesce(trim(p_student_id), '')) = 0 or length(p_student_id) > 30 then
    raise exception 'Enter your student ID';
  end if;
  if lower(p_username) = 'everyone' then
    raise exception 'That username is reserved';
  end if;
  if exists (select 1 from accounts where lower(username) = lower(p_username)) then
    raise exception 'That username is taken';
  end if;
  insert into accounts (username, password, student_id)
  values (p_username, crypt(p_password, gen_salt('bf')), trim(p_student_id));
end;
$$;

create or replace function public.hbu_login(p_username text, p_password text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare real_name text;
begin
  select username into real_name from accounts
   where lower(username) = lower(p_username) and password = crypt(p_password, password);
  if real_name is null then
    raise exception 'Wrong username or password';
  end if;
  return real_name;
end;
$$;

-- Send to the main chat (p_receiver = 'everyone') or DM a user.
create or replace function public.hbu_send(p_username text, p_password text, p_receiver text, p_message text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare sender text; target text;
begin
  select username into sender from accounts
   where lower(username) = lower(p_username) and password = crypt(p_password, password);
  if sender is null then raise exception 'Wrong username or password'; end if;
  if length(trim(coalesce(p_message, ''))) = 0 or length(p_message) > 500 then
    raise exception 'Message must be 1-500 characters';
  end if;
  if lower(coalesce(p_receiver, 'everyone')) = 'everyone' then
    target := 'everyone';
  else
    select username into target from accounts where lower(username) = lower(p_receiver);
    if target is null then raise exception 'That user does not exist'; end if;
    if target = sender then raise exception 'You cannot DM yourself'; end if;
  end if;
  insert into messages ("user", message, receiver) values (sender, trim(p_message), target);
end;
$$;

-- Conversation between the caller and p_other.
create or replace function public.hbu_get_dms(p_username text, p_password text, p_other text)
returns table ("user" text, message text, created_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
declare me text;
begin
  select username into me from accounts
   where lower(username) = lower(p_username) and password = crypt(p_password, password);
  if me is null then raise exception 'Wrong username or password'; end if;
  return query
    select t."user", t.message, t.created_at from (
      select m."user", m.message, m.created_at from messages m
       where (m."user" = me and lower(m.receiver) = lower(p_other))
          or (lower(m."user") = lower(p_other) and m.receiver = me)
       order by m.created_at desc limit 100
    ) t order by t.created_at asc;
end;
$$;

-- People the caller has DM'd or been DM'd by.
create or replace function public.hbu_dm_partners(p_username text, p_password text)
returns table (partner text)
language plpgsql security definer set search_path = public, extensions as $$
declare me text;
begin
  select username into me from accounts
   where lower(username) = lower(p_username) and password = crypt(p_password, password);
  if me is null then raise exception 'Wrong username or password'; end if;
  return query
    select distinct case when m."user" = me then m.receiver else m."user" end
      from messages m
     where m.receiver <> 'everyone' and (m."user" = me or m.receiver = me);
end;
$$;

grant execute on function
  public.hbu_signup(text, text, text),
  public.hbu_login(text, text),
  public.hbu_send(text, text, text, text),
  public.hbu_get_dms(text, text, text),
  public.hbu_dm_partners(text, text)
to anon, authenticated;
