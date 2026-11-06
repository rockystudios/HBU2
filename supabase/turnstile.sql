-- Run AFTER redeploying send-message. Signups must now go through the Edge
-- Function (which checks Cloudflare Turnstile), so bots can't call hbu_signup directly.
revoke execute on function public.hbu_signup(text, text, text) from anon, authenticated, public;
grant execute on function public.hbu_signup(text, text, text) to service_role;
