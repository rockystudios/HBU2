# HBU2

## Message archives

Run `supabase/message-archives.sql` in the Supabase SQL editor after deploying the updated `send-message` function. New global chat messages keep the newest 100 in chat; older messages are moved atomically into owner-only JSON archives. Private messages are not archived. The Owner app can display, copy, and permanently delete each archive. If an archive changes after it is viewed, refresh and copy it again before deleting it.

## Signup verification

The signup form uses the locally hosted ALTCHA widget. Configure the `ALTCHA_HMAC_SECRET` Edge Function secret and run `supabase/altcha.sql` for signup verification and single-use challenges. A working Supabase project and a deployed `send-message` function with Verify JWT disabled are required.

If both login and verification cannot reach the account service, check in the Supabase dashboard that project `xvkjvuxhawlljakfkllu` is active and that the site's project URL and publishable key are current. If verification reports that signup protection is not configured or set up, check the function secret and SQL setup above. After changing the function or its settings, redeploy it and verify that both login and signup work.

Open `connection-test.html` on the deployed site to check database access, login RPCs, and signup verification from the affected browser without entering credentials. Browser request failures may indicate a network, CORS, or blocking issue rather than a specific server failure.