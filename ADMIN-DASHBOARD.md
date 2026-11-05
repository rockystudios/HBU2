# Central admin dashboard

`admin.html` is a responsive, standalone management console. It uses the existing HBU account login and does not create password-only access or retain credentials in browser storage. Every dashboard request is authenticated again by the `admin-dashboard` Supabase Edge Function; only accounts listed in the server-side `ADMIN_USERNAMES` secret can use it (default: `rocky`). Management changes are written to the private `admin_audit_log` table.

## Setup

1. In the Supabase SQL Editor, run `supabase/admin-dashboard.sql`.
2. Deploy `supabase/functions/admin-dashboard/index.ts` as the `admin-dashboard` Edge Function.
3. Set the Supabase Edge Function secrets `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `ADMIN_USERNAMES` (a comma-separated list of existing HBU usernames; do not put passwords in secrets or source code). Supabase supplies the first two automatically in the usual Edge Function environment.
4. Optionally set `ADMIN_DASHBOARD_ORIGINS` to the exact HTTPS site origin(s), comma separated, to restrict browser CORS. It defaults to `*`; the endpoint still requires the existing account password and server-side admin allowlist.
5. Publish the site and visit `/admin.html`. Sign in with an existing admin account.

The dashboard includes account search, ban/unban, role assignment, word-filter management, and audit history. It deliberately omits account passwords, student IDs, and private messages. Use a unique, strong password for the admin account and rotate any password that has been shared.
