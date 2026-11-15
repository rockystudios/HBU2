# HBU2 Security Lockdown Runbook

## What this does

HBU2's browser traffic is routed through the Cloudflare Worker. The Worker now:
- Applies lower per-IP and per-device limits before forwarding.
- Requires a server-side secret named `HBU_GATEWAY_TOKEN`.
- Adds the secret to requests sent to Supabase; it is never sent to browser JavaScript.
- Passes a trusted client IP to the Edge Function.

The `send-message` Edge Function now rejects requests without the same secret.
The SQL migration `supabase/gateway-lockdown.sql` installs a PostgREST pre-request check so direct REST/RPC calls that bypass Cloudflare are rejected.

**The shared-secret layer is not active until the secret is configured in both dashboards and the SQL migration is run. The Worker fails closed (503) if its secret is missing.**

## 1. Set the shared secret

Use the exact 64-character token supplied to the project owner in the private incident-response conversation. The SQL file in this commit already contains the SHA-256 hash for that exact token. Generating a different token will not match the SQL migration unless its hash is updated first.

Do not put this token in `index.html`, any other browser file, a GitHub commit, or a public issue. Store it only as a Secret in Cloudflare and Supabase.

### Cloudflare Worker secret
1. Cloudflare Dashboard → Workers & Pages → Worker **hbu2**.
2. Settings → Variables and Secrets → Add.
3. Choose **Secret**.
4. Name: `HBU_GATEWAY_TOKEN`
5. Value: paste the generated token and save.

### Supabase Edge Function secret
1. Supabase Dashboard → Project → Edge Functions → Secrets.
2. Add secret named `HBU_GATEWAY_TOKEN`.
3. Paste the exact same token and save.

The updated Edge Function source is in `supabase/functions/send-message/index.ts`. Deploy the `send-message` function after setting the secret.

## 2. Apply the database-side gateway gate

When the Supabase SQL Editor can connect again:
1. Open `supabase/gateway-lockdown.sql` from this repository.
2. Run the complete SQL script once.
3. It stores only the SHA-256 hash of the token generated for this deployment.
4. The script registers `public.hbu_require_gateway_token()` as PostgREST's `db_pre_request`.

It allows server-side `service_role` requests and requires the shared token for normal Data API requests. This protects the Data API only; the Edge Function has its own token check. RLS and least-privilege grants remain required.

Also verify whether `supabase/security-hardening.sql` was previously applied. Its presence in GitHub does not prove it has been executed in the database.

## 3. Protect the source repository

The repository is public so its website files can be downloaded. That is normal for a static site. Downloading files does not give someone permission to change the official GitHub Pages site.

The `main` branch was checked on 2026-11-15 and is currently **not protected**. In GitHub:
1. Open **rockystudios/HBU2 → Settings → Branches**.
2. Add a branch protection rule for `main`.
3. Require pull requests before merging.
4. Keep force pushes disabled and branch deletion disabled.
5. Enable **Do not allow bypassing the above settings** (including administrators).
6. Save the rule.

Also review Settings → Collaborators and teams; remove anyone you do not recognize. In your GitHub account settings, enable two-factor authentication/passkey, review active sessions, and revoke unknown personal access tokens and authorized apps.

## 4. If traffic is still attacking the project

The Supabase screenshot showed 35,880 API Gateway requests and 35,874 errors in the selected 60-minute window, plus an organization quota warning. If the database remains unreachable and the traffic is still ongoing, the fastest platform-level stop is to **pause the Free Supabase project** from Settings → General → Project availability. This takes HBU2 offline, but Supabase documents that pausing preserves the project data and it can be resumed later. Only do this if you accept the site being offline while the database-side gate is installed.

## 5. Verification

After the shared secret and SQL gate are all active:
- Requests to the Worker from HBU2 should work.
- Calling the Supabase REST URL directly without the secret should return HTTP 403.
- Calling the Supabase Edge Function directly without the secret should return HTTP 403.
- The website's connection test should reach the database and image challenge.
- Recheck Supabase API Gateway metrics after deployment. A falling request/error rate is the success signal; deployment alone is not proof that abuse has stopped.
