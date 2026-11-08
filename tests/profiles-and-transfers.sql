-- Run only against an empty, disposable PostgreSQL database:
-- psql -v ON_ERROR_STOP=1 -f tests/profiles-and-transfers.sql
begin;
create schema if not exists extensions;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
end $$;
create table public.accounts (username text primary key, password text not null, coins integer not null check (coins >= 0));
create table public.social_follows (follower text not null, followee text not null);
create function public.hbu_login(p_username text, p_password text) returns text language plpgsql as $$
declare who text;
begin
  select username into who from accounts where lower(username) = lower(p_username) and password = p_password;
  if who is null then raise exception 'Wrong username or password'; end if;
  return who;
end $$;
insert into public.accounts values ('Alice', 'secret', 100), ('Bob', 'secret', 10), ('Carol', 'secret', 2147483640);
insert into public.social_follows values ('Bob', 'Alice'), ('Carol', 'Alice');
\ir ../supabase/profiles-and-transfers.sql

do $$
declare result jsonb; total bigint;
begin
  result := public.hbu_profile_followers('alice', 'secret', 'ALICE');
  if result <> '["Bob", "Carol"]'::jsonb then raise exception 'Unexpected followers: %', result; end if;
  result := public.hbu_transfer_coins('alice', 'secret', 'bob', 35);
  if result <> '{"username":"Bob","coins":65,"amount":35}'::jsonb then raise exception 'Unexpected transfer: %', result; end if;
  if (select coins from accounts where username = 'Bob') <> 45 then raise exception 'Wrong recipient balance'; end if;
  begin
    perform public.hbu_transfer_coins('Alice', 'wrong', 'Bob', 1);
    raise exception 'Wrong password accepted';
  exception when others then if sqlerrm <> 'Wrong username or password' then raise; end if; end;
  begin
    perform public.hbu_transfer_coins('Alice', 'secret', 'alice', 1);
    raise exception 'Self transfer accepted';
  exception when others then if sqlerrm <> 'You cannot send coins to yourself.' then raise; end if; end;
  begin
    perform public.hbu_transfer_coins('Alice', 'secret', 'Bob', 0);
    raise exception 'Zero accepted';
  exception when others then if sqlerrm <> 'Enter a positive whole number of coins.' then raise; end if; end;
  begin
    perform public.hbu_transfer_coins('Alice', 'secret', 'Bob', -1);
    raise exception 'Negative amount accepted';
  exception when others then if sqlerrm <> 'Enter a positive whole number of coins.' then raise; end if; end;
  begin
    perform public.hbu_transfer_coins('Alice', 'secret', 'Bob', 66);
    raise exception 'Insufficient balance accepted';
  exception when others then if sqlerrm <> 'Not enough coins.' then raise; end if; end;
  begin
    perform public.hbu_transfer_coins('Alice', 'secret', 'Carol', 8);
    raise exception 'Overflow accepted';
  exception when others then if sqlerrm <> 'The recipient cannot hold that many coins.' then raise; end if; end;
  begin
    perform public.hbu_transfer_coins('Alice', 'secret', 'Unknown', 1);
    raise exception 'Unknown user accepted';
  exception when others then if sqlerrm <> 'That user does not exist.' then raise; end if; end;
  select sum(coins::bigint) into total from accounts;
  if total <> 2147483750 or (select coins from accounts where username = 'Alice') <> 65 then
    raise exception 'Balances changed after a rejected transfer';
  end if;
end $$;
\if :{?persist_fixture}
commit;
\else
rollback;
\endif
