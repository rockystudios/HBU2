-- Run after accounts-and-dms.sql, coins.sql and social.sql.
-- Safe to run again. No Edge Function deployment is needed.

create or replace function public.hbu_profile_followers(p_username text, p_password text, p_target text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; target text; followers jsonb;
begin
  who := public.hbu_login(p_username, p_password);
  select username into target from accounts where lower(username) = lower(trim(coalesce(p_target, '')));
  if target is null then raise exception 'That user does not exist.'; end if;
  select coalesce(jsonb_agg(f.username order by lower(f.username)), '[]'::jsonb) into followers
  from (
    select a.username
    from social_follows s join accounts a on lower(a.username) = lower(s.follower)
    where lower(s.followee) = lower(target)
    order by lower(a.username)
    limit 100
  ) f;
  return followers;
end;
$$;

create or replace function public.hbu_transfer_coins(p_username text, p_password text, p_target text, p_amount integer)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare who text; target text; sender_balance integer; recipient_balance integer; locked_count integer;
begin
  who := public.hbu_login(p_username, p_password);
  if p_amount is null or p_amount <= 0 then raise exception 'Enter a positive whole number of coins.'; end if;
  select username into target from accounts where lower(username) = lower(trim(coalesce(p_target, '')));
  if target is null then raise exception 'That user does not exist.'; end if;
  if lower(target) = lower(who) then raise exception 'You cannot send coins to yourself.'; end if;

  perform username from accounts where username in (who, target) order by lower(username) for update;
  get diagnostics locked_count = row_count;
  if locked_count <> 2 then raise exception 'An account no longer exists. Try again.'; end if;
  select coins into sender_balance from accounts where username = who;
  select coins into recipient_balance from accounts where username = target;
  if sender_balance < p_amount then raise exception 'Not enough coins.'; end if;
  if recipient_balance > 2147483647 - p_amount then raise exception 'The recipient cannot hold that many coins.'; end if;

  update accounts set coins = coins - p_amount where username = who returning coins into sender_balance;
  update accounts set coins = coins + p_amount where username = target;
  return jsonb_build_object('username', target, 'coins', sender_balance, 'amount', p_amount);
end;
$$;

revoke all on function public.hbu_profile_followers(text, text, text), public.hbu_transfer_coins(text, text, text, integer) from public;
grant execute on function public.hbu_profile_followers(text, text, text), public.hbu_transfer_coins(text, text, text, integer) to anon, authenticated;
notify pgrst, 'reload schema';
