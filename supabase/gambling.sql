-- Casino app: coin flip, dice and slots using coins. Run once in the Supabase SQL editor. No Edge Function change needed.
-- All rolls happen here on the server so players can't cheat from the browser. Safe to run again.

create or replace function public.hbu_gamble(p_username text, p_password text, p_game text, p_bet integer, p_pick text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  who text; have int; payout int := 0; total int; roll int; res jsonb;
  sym text[] := array['🍒','🍋','🔔','⭐','💎','7️⃣']; r1 int; r2 int; r3 int;
begin
  who := public.hbu_login(p_username, p_password);
  if p_bet is null or p_bet < 1 or p_bet > 1000 then raise exception 'Bet between 1 and 1000 coins.'; end if;
  select coins into have from accounts where username = who for update;
  if have < p_bet then raise exception 'Not enough coins.'; end if;

  if p_game = 'flip' then
    if p_pick not in ('heads','tails') then raise exception 'Pick heads or tails.'; end if;
    roll := floor(random() * 100)::int;
    -- 48% win, pays 2x
    if roll < 48 then payout := p_bet * 2; res := jsonb_build_object('side', p_pick);
    else res := jsonb_build_object('side', case when p_pick = 'heads' then 'tails' else 'heads' end); end if;
  elsif p_game = 'dice' then
    if p_pick not in ('high','low') then raise exception 'Pick high or low.'; end if;
    roll := floor(random() * 100)::int + 1;
    -- low = 1-48, high = 53-100 (49 to 52 always loses), pays 2x
    if (p_pick = 'low' and roll <= 48) or (p_pick = 'high' and roll >= 53) then payout := p_bet * 2; end if;
    res := jsonb_build_object('roll', roll);
  elsif p_game = 'slots' then
    r1 := floor(random() * 6)::int + 1; r2 := floor(random() * 6)::int + 1; r3 := floor(random() * 6)::int + 1;
    if r1 = r2 and r2 = r3 then payout := p_bet * (case when r1 = 6 then 20 else 8 end);
    elsif r1 = r2 or r2 = r3 or r1 = r3 then payout := (p_bet * 3) / 2; end if;
    res := jsonb_build_object('reels', jsonb_build_array(sym[r1], sym[r2], sym[r3]));
  else
    raise exception 'Unknown game.';
  end if;

  update accounts set coins = coins - p_bet + payout where username = who returning coins into total;
  return res || jsonb_build_object('payout', payout, 'bet', p_bet, 'coins', total, 'won', payout > p_bet);
end;
$$;

grant execute on function public.hbu_gamble(text, text, text, integer, text) to anon, authenticated;
notify pgrst, 'reload schema';
