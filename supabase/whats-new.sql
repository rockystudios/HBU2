-- Per-account dismissal state for the HBU What's New announcement.
-- Run once in the Supabase SQL editor.

create table if not exists public.hbu_whats_new_dismissals (
  username text primary key,
  notice_id text not null,
  dismissed_at timestamptz not null default now()
);

alter table public.hbu_whats_new_dismissals enable row level security;
revoke all on public.hbu_whats_new_dismissals from anon, authenticated;
grant all on public.hbu_whats_new_dismissals to service_role;

create or replace function public.hbu_whats_new_status(
  p_username text,
  p_password text,
  p_notice_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  who text;
  saved_notice text;
begin
  who := public.hbu_login(p_username, p_password);
  if p_notice_id is null or length(trim(p_notice_id)) < 1 or length(trim(p_notice_id)) > 80 then
    raise exception 'Invalid announcement identifier.';
  end if;
  select notice_id into saved_notice
    from public.hbu_whats_new_dismissals
    where username = who;
  return jsonb_build_object('show', saved_notice is distinct from p_notice_id);
end;
$$;

create or replace function public.hbu_whats_new_dismiss(
  p_username text,
  p_password text,
  p_notice_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare who text;
begin
  who := public.hbu_login(p_username, p_password);
  if p_notice_id is null or length(trim(p_notice_id)) < 1 or length(trim(p_notice_id)) > 80 then
    raise exception 'Invalid announcement identifier.';
  end if;
  insert into public.hbu_whats_new_dismissals (username, notice_id, dismissed_at)
  values (who, p_notice_id, now())
  on conflict (username) do update
    set notice_id = excluded.notice_id, dismissed_at = excluded.dismissed_at;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.hbu_whats_new_status(text, text, text) from public;
revoke all on function public.hbu_whats_new_dismiss(text, text, text) from public;
grant execute on function public.hbu_whats_new_status(text, text, text) to anon, authenticated;
grant execute on function public.hbu_whats_new_dismiss(text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
