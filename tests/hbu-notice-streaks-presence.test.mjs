import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const [home, edge, noticeSql, gamblingSql] = await Promise.all([
  readFile(new URL("index.html", root), "utf8"),
  readFile(new URL("supabase/functions/send-message/index.ts", root), "utf8"),
  readFile(new URL("supabase/whats-new.sql", root), "utf8"),
  readFile(new URL("supabase/gambling-streak-boost.sql", root), "utf8"),
]);

test("staff policy gate waits for the server check before it appears", () => {
  const setupStart = home.indexOf("async function setupStaff()");
  const setupEnd = home.indexOf("\n    function ", setupStart + 1);
  const setup = home.slice(setupStart, setupEnd);
  assert.doesNotMatch(setup, /showRolePolicyGate\(""\)/);
  assert.match(home, /if \(status\.required\)[\s\S]*?showRolePolicyGate/);
});

test("What's New is account-backed and requires three seconds before dismissal", () => {
  assert.match(home, /WHATS_NEW_ID/);
  assert.match(home, /hbu_whats_new_status/);
  assert.match(home, /hbu_whats_new_dismiss/);
  assert.match(home, /}, 3000\)/);
  assert.match(noticeSql, /hbu_whats_new_dismissals/);
  assert.match(noticeSql, /saved_notice is distinct from p_notice_id/);
  assert.match(noticeSql, /grant execute on function public\.hbu_whats_new_dismiss/);
});

test("Casino odds and streak rewards are enforced by server-side SQL", () => {
  assert.match(gamblingSql, /roll < 52/);
  assert.match(gamblingSql, /roll <= 52/);
  assert.match(gamblingSql, /new_streak % 3 = 0/);
  assert.match(gamblingSql, /new_streak % 7 = 0/);
  assert.match(gamblingSql, /Free name plate/);
  assert.match(home, /52% win chance on Coin Flip and Dice/);
});

test("Owner presence monitor only exposes an owner-protected presence action", () => {
  assert.match(home, /adminCall\("admin_owner_presence"\)/);
  assert.match(home, /hbu-owner-presence-tracked/);
  assert.match(edge, /action === "admin_owner_presence"/);
  assert.match(edge, /Only the owner can monitor account presence/);
  assert.match(edge, /hbu_presence\?select=username,last_seen/);
});
