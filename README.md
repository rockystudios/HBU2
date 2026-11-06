# HBU2

## Message archives

Run `supabase/message-archives.sql` in the Supabase SQL editor after deploying the updated `send-message` function. New global chat messages keep the newest 100 in chat; older messages are moved atomically into owner-only JSON archives. Private messages are not archived. The Owner app can display, copy, and permanently delete each archive. If an archive changes after it is viewed, refresh and copy it again before deleting it.

## Signup verification

The signup form uses an image challenge checked by the `send-message` Edge Function. No SQL is needed for the image check (it is stateless; `supabase/image-verification.sql` is now optional). Keep the `ALTCHA_HMAC_SECRET` Edge Function secret configured, then deploy the updated `send-message` function with Verify JWT disabled and deploy the site. Existing ALTCHA files and endpoints are retained for older clients. Challenges expire after five minutes and are consumed on the first valid-format answer attempt. Mouse movement is counted only in the browser and is not required or sent to the server.

The image contains SVG text, so this basic custom check is not strong protection against automated signup. It also has no nonvisual alternative; users unable to read the image cannot complete signup. Use a stronger, accessible verification service if these limitations are unacceptable.

If both login and verification cannot reach the account service, check in the Supabase dashboard that project `xvkjvuxhawlljakfkllu` is active and that the site's project URL and publishable key are current. If verification reports that signup protection is not configured or set up, check the function secret and SQL setup above. After changing the function or its settings, redeploy it and verify that both login and signup work.

Open `connection-test.html` on the deployed site to check database access, login RPCs, and signup verification from the affected browser without entering credentials. Browser request failures may indicate a network, CORS, or blocking issue rather than a specific server failure.