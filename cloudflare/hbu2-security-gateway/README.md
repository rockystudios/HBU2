# HBU2 Security Gateway

This folder contains a Cloudflare Worker and a SQLite-backed Durable Object rate limiter. The HBU2 frontend has been changed to send its Supabase REST and Edge Function requests through this gateway.

## Supported origins

- `https://rockystudios.github.io`
- `http://hbu2.s3-website.us-east-2.amazonaws.com`
- `https://hbu2.s3-website.us-east-2.amazonaws.com`

## Deploy the gateway

1. Install Node.js.
2. Open a terminal in `cloudflare/hbu2-security-gateway`.
3. Run:

   ```bash
   npm install -g wrangler
   wrangler login
   wrangler deploy
   ```

4. Cloudflare prints a URL similar to `https://hbu2-security-gateway.YOUR-SUBDOMAIN.workers.dev`.
5. Open both `index.html` and `connection-test.html` and replace:

   `https://YOUR-WORKER-NAME.YOUR-CLOUDFLARE-SUBDOMAIN.workers.dev`

   with the exact Worker URL. This placeholder is intentional: the project cannot know your Cloudflare account subdomain before deployment.
6. Commit and publish the updated website files.

## Rate limits

| Endpoint class | Per IP | Per device | Window |
|---|---:|---:|---:|
| Image challenge | 180 | 30 | 1 minute |
| Login | 120 | 10 | 15 minutes |
| Signup | 60 | 5 | 1 hour |
| Other Edge Function requests | 900 | 180 | 1 minute |
| RPC | 1200 | 240 | 1 minute |
| REST | 1500 | 300 | 1 minute |

The login/signup limits are selected by inspecting the `action` in the send-message JSON body, since this project uses one Edge Function for those operations.

## What the frontend change does

- Replaces the direct Supabase REST and Functions base URLs with the Worker URL.
- Sends the existing first-party `hbu-device-id-v1` UUID as `X-HBU-Device-ID` on gateway requests.
- Routes the connection test through the gateway too.

## Critical limitations

- This is an additional abuse-control layer, not a way to make the public Supabase project URL private. The publishable key and project URL are visible to browsers. A determined client can bypass this Worker and call Supabase directly unless direct database access is independently secured. Keep RLS enabled and verify grants/policies on every exposed table and RPC. Never put a service-role key in frontend code.
- Device IDs are user-controlled and can be reset or spoofed. They are a rate-limit signal, not authentication.
- IP limits may affect multiple legitimate users sharing a school or household network. Adjust limits after observing real traffic.
- The gateway currently proxies only `/rest/v1/*` and `/functions/v1/send-message`. It does not proxy Supabase Auth, Storage, Realtime, or other endpoints.
- Rate-limit storage is fail-closed: if Durable Object checks fail, the Worker returns 503 and does not forward to Supabase.


IP thresholds are deliberately higher because school and household networks can share one public IP address. The per-device thresholds are tighter. Monitor real traffic and tune these numbers before treating them as final policy.
