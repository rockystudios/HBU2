-- Archive global chat messages beyond the newest 100. Private messages are untouched.
-- Run in the Supabase SQL editor after deploying the updated Edge Function.
create table if not exists public.hbu_message_archives (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  message_count integer not null,
  messages jsonb not null
);

alter table public.hbu_message_archives enable row level security;
revoke all on public.hbu_message_archives from public, anon, authenticated;
grant select, delete on public.hbu_message_archives to service_role;

create index if not exists hbu_messages_global_archive_idx
  on public.messages (created_at desc nulls last, id desc)
  where receiver = 'everyone';

create or replace function public.hbu_archive_old_messages()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  archived jsonb;
  archived_count integer;
  archive_id bigint;
begin
  if new.receiver <> 'everyone' then
    return new;
  end if;

  perform pg_advisory_xact_lock(794627104);

  with old_ids as (
    select id
      from public.messages
     where receiver = 'everyone'
     order by created_at desc nulls last, id desc
     offset 100
  ), removed as (
    delete from public.messages m
     using old_ids
     where m.id = old_ids.id
     returning m.*
  )
  select jsonb_agg(to_jsonb(removed) order by created_at, id), count(*)::integer
    into archived, archived_count
    from removed;

  if archived_count > 0 then
    select id into archive_id
      from public.hbu_message_archives
     where message_count + archived_count <= 100
     order by id desc
     limit 1
     for update;
    if archive_id is null then
      insert into public.hbu_message_archives (message_count, messages)
      values (archived_count, archived);
    else
      update public.hbu_message_archives
         set messages = messages || archived,
             message_count = message_count + archived_count
       where id = archive_id;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.hbu_archive_old_messages() from public, anon, authenticated;
drop trigger if exists hbu_archive_old_messages on public.messages;
create trigger hbu_archive_old_messages
  after insert on public.messages
  for each row execute function public.hbu_archive_old_messages();

notify pgrst, 'reload schema';
