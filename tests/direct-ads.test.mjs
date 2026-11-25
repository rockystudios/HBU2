import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const [home, form, migration, edge] = await Promise.all([
  readFile(new URL("index.html", root), "utf8"),
  readFile(new URL("advertise.html", root), "utf8"),
  readFile(new URL("supabase/advertising.sql", root), "utf8"),
  readFile(new URL("supabase/functions/send-message/index.ts", root), "utf8"),
]);

test("HBU home banner is a first-party advertiser invitation and no external ad scripts remain", () => {
  assert.match(home, /id="home-ad-link" href="advertise\.html"/);
  assert.match(home, /src="assets\/ad-your-here\.svg"/);
  assert.match(home, /From HBU/);
  assert.doesNotMatch(home, /adsterra|abscloud\.org|bauval\.org|atOptions|popunder/i);
  assert.doesNotMatch(home, /home-ad-slot|arcade-ad-slot/);
});

test("advertiser form collects image, HTTPS destination, contact and duration", () => {
  assert.match(form, /type="file" accept="image\/png,image\/jpeg,image\/webp,image\/gif"/);
  assert.match(form, /https:\/\/example\.com/);
  assert.match(form, /Rocky will reach out to you about payments shortly/);
  assert.match(form, /account-username/);
  assert.match(form, /account-password/);
  assert.match(form, /submit_ad/);
  assert.match(form, /X-HBU-Device-ID/);
  assert.match(form, /650 \* 1024/);
});

test("database keeps requests private and only exposes the current approved ad", () => {
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /revoke all on public\.hbu_ad_requests from anon, authenticated/i);
  assert.match(migration, /status = 'approved'/);
  assert.match(migration, /expires_at > now\(\)/);
  assert.match(migration, /grant execute on function public\.hbu_submit_ad/);
});

test("Owner review actions are explicitly owner-only", () => {
  assert.match(edge, /admin_owner_ad_list/);
  assert.match(edge, /admin_owner_ad_get/);
  assert.match(edge, /admin_owner_ad_review/);
  assert.match(edge, /staff\.toLowerCase\(\) !== "rocky"/);
});
