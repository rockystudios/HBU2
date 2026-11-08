# HBU2

## Advertising

The home screen contains one 300×250 Adsterra banner in its supplied placement. The ad script is supplied by Adsterra and may be blocked by browsers or ad blockers; the rest of the site does not depend on it. Review Adsterra's ad-content settings and applicable privacy and consent requirements before enabling ads for the site's audience.

Settings offers optional Adsterra popunder ads, off by default and saved in the browser. The script loads early on page load only after opt-in and not on phones or screens at most 650px wide. Popunders open behind the current page and may appear while Arcade is open. Changing the setting or crossing the narrow-screen threshold reloads the page; the reload is needed to start or stop the provider script. Settings reports script loading errors and offers a reload to retry. Loading the script does not guarantee an ad: the ad provider controls availability and timing, and browser or content blockers may prevent ads from loading or opening.

The Settings pop-up test opens a local test window, not an advertisement. It checks whether the browser permits a directly requested window; a successful test does not guarantee Adsterra popunders can open or that ads are available.

Student ID is completely optional when creating an account. Run `supabase/optional-student-id.sql` once in the Supabase SQL editor to update the signup function in an existing project.

## Dev role

The Dev role has a `</>` chat badge and no staff access or extra commands by default. For an existing role-editor setup, run `supabase/dev-role.sql` in the Supabase SQL editor; new setups get it from `supabase/role-editor.sql`. An existing Dev role is not overwritten. The owner can assign the role from the moderation panel and edit its permissions in the Owner app.

## Chat tips

Mod-bot shows a rotating tip in the main chat after one minute with chat open, then every five minutes of main-chat viewing. Tips are local to the current session, are visible only to you, and are not posted to the database or shown in DMs.

Direct messages are ordered by the latest sent or received message, with an unread dot for conversations containing a new incoming message. The dot clears after that conversation is loaded while Chat is visible. Read state is saved per account in this browser, not synchronized between devices. The inbox summary is used when available; otherwise the site checks individual conversations less frequently.

The emoji picker includes [Twemoji](https://github.com/twitter/twemoji) graphics by Twitter, Inc. and other contributors, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), and animated Otto robot GIFs by 小鹏 from [otto-emoji-gif-component](https://github.com/txp666/otto-emoji-gif-component), licensed under the MIT license included in `assets/emoji/otto/LICENSE`.

## Home screen

Use **Show apps** to filter by category, and **Manage pins** to pin favorite apps to the front or view only pinned apps. Pins are saved in this browser on this device. Player-made apps appear in the Player apps category when installed; unavailable apps stay hidden.

## Paint

Paint includes separate brush and eraser size controls, a fill tool for connected areas, and Pick color to sample the canvas. Undo and redo retain up to 15 drawing, fill, or clear actions while the page is open. Save PNG downloads the canvas.

## Profiles and coin transfers

After `supabase/accounts-and-dms.sql`, `supabase/coins.sql`, and `supabase/social.sql` are installed, run `supabase/profiles-and-transfers.sql` in the Supabase SQL editor. No Edge Function update is needed. Open the Profiles app and enter a username to see their profile picture, follower count, and equipped nameplate background. HBU Social also shows profiles and up to 100 follower names. Profiles require login. Rewards is always available on the home screen; logged-in users can send positive whole-number coin amounts to another account. Transfers are atomic and cannot be undone. If a request cannot be confirmed, check your balance before trying again.

## Nameplates

New setups receive all nameplates from `supabase/coins.sql`. For an existing setup, run `supabase/new-nameplates.sql` once in the Supabase SQL editor to add ten more plates; it preserves existing plates and ownership. No Edge Function update is needed.

## Message archives

Run `supabase/message-archives.sql` in the Supabase SQL editor after deploying the updated `send-message` function. New global chat messages keep the newest 100 in chat; older messages are moved atomically into owner-only JSON archives. Private messages are not archived. The Owner app can display, copy, and permanently delete each archive. If an archive changes after it is viewed, refresh and copy it again before deleting it.

## Login and signup verification

The login and signup forms use an image challenge checked by the `send-message` Edge Function. Keep the `ALTCHA_HMAC_SECRET` Edge Function secret configured and deploy the updated function with Verify JWT disabled **before** deploying the site. Run `supabase/image-verification.sql` to restrict direct account creation to the function, if it has not already been run. Existing ALTCHA files and endpoints are retained for older clients. Challenges expire after five minutes. Attempts are remembered only in each function instance's memory, so a restart or another instance can allow reuse. Mouse movement is counted only in the browser and is not required or sent to the server.

The image contains SVG text, so this basic custom check is not strong protection against automation. The public login RPC and other credential-accepting RPCs remain accessible for existing clients and features, so it can also be bypassed outside the website. It has no nonvisual alternative; users unable to read the image cannot complete login or signup. Use a stronger, accessible verification service and a different authentication architecture if these limitations are unacceptable.

The site preloads a verification image while signed out and reuses a fresh image when switching between login and signup. If the image is too old, a fresh one is requested. If both login and verification cannot reach the account service, use **Test account connection** on the login screen and check in the Supabase dashboard that project `xvkjvuxhawlljakfkllu` is active and that the site's project URL and publishable key are current. If verification reports that it is not configured, check the function secret. After changing the function or its settings, redeploy it and verify that both login and signup work.

Open `connection-test.html` on the deployed site to check database access, login RPCs, and signup verification from the affected browser without entering credentials. Browser request failures may indicate a network, CORS, or blocking issue rather than a specific server failure.