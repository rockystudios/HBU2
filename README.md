# HBU2

## Advertising

The home screen contains one 300×250 Adsterra banner in its supplied placement. The ad script is supplied by Adsterra and may be blocked by browsers or ad blockers; the rest of the site does not depend on it. Review Adsterra's ad-content settings and applicable privacy and consent requirements before enabling ads for the site's audience.

Student ID is completely optional when creating an account. Run `supabase/optional-student-id.sql` once in the Supabase SQL editor to update the signup function in an existing project.

## Chat tips

Mod-bot shows a rotating tip in the main chat after one minute with chat open, then every five minutes of main-chat viewing. Tips are local to the current session, are visible only to you, and are not posted to the database or shown in DMs. Offline mode does not show them.

## Message archives

Run `supabase/message-archives.sql` in the Supabase SQL editor after deploying the updated `send-message` function. New global chat messages keep the newest 100 in chat; older messages are moved atomically into owner-only JSON archives. Private messages are not archived. The Owner app can display, copy, and permanently delete each archive. If an archive changes after it is viewed, refresh and copy it again before deleting it.

## Login and signup verification

The login and signup forms use an image challenge checked by the `send-message` Edge Function. Keep the `ALTCHA_HMAC_SECRET` Edge Function secret configured and deploy the updated function with Verify JWT disabled **before** deploying the site. Run `supabase/image-verification.sql` to restrict direct account creation to the function, if it has not already been run. Existing ALTCHA files and endpoints are retained for older clients. Challenges expire after five minutes. Attempts are remembered only in each function instance's memory, so a restart or another instance can allow reuse. Mouse movement is counted only in the browser and is not required or sent to the server.

The image contains SVG text, so this basic custom check is not strong protection against automation. The public login RPC and other credential-accepting RPCs remain accessible for existing clients and features, so it can also be bypassed outside the website. It has no nonvisual alternative; users unable to read the image cannot complete login or signup. Use a stronger, accessible verification service and a different authentication architecture if these limitations are unacceptable.

If both login and verification cannot reach the account service, check in the Supabase dashboard that project `xvkjvuxhawlljakfkllu` is active and that the site's project URL and publishable key are current. If verification reports that it is not configured, check the function secret. After changing the function or its settings, redeploy it and verify that both login and signup work.

Open `connection-test.html` on the deployed site to check database access, login RPCs, and signup verification from the affected browser without entering credentials. Browser request failures may indicate a network, CORS, or blocking issue rather than a specific server failure.