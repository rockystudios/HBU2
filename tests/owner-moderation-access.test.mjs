import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const server = await readFile(new URL("../supabase/functions/send-message/index.ts", import.meta.url), "utf8");
const page = await readFile(new URL("../index.html", import.meta.url), "utf8");

test("ban, unban, and banlist slash commands are owner-only", () => {
  for (const [command, next] of [["ban", "unban"], ["unban", "mute"], ["banlist", "mutelist"]]) {
    const block = server.match(new RegExp(`\\n  ${command}: \\{([\\s\\S]*?)\\n  ${next}: \\{`))?.[1];
    assert.ok(block, `missing /${command} command definition`);
    assert.match(block, /roles:\s*\["admin"\]/);
  }
});

test("ban API and active-ban details are restricted to the owner", () => {
  const banHandler = server.match(/if \(action === "admin_ban"\) \{([\s\S]*?)\n  \}\n  throw new UserError\("Unknown action\."\);/)?.[1];
  assert.ok(banHandler, "missing admin_ban handler");
  assert.match(banHandler, /adminOnly\(\)/);

  const listHandler = server.match(/if \(action === "admin_list"\) \{([\s\S]*?)\n  \}\n  if \(action === "admin_delete"\)/)?.[1];
  assert.ok(listHandler, "missing admin_list handler");
  assert.match(listHandler, /role === "admin"\s*\?\s*await db\([\s\S]*?:\s*\[\]/);
});

test("ban controls are hidden for non-admin staff, while role editing stays owner-only", () => {
  assert.match(page, /id="admin-ban-section" hidden/);
  assert.match(page, /adminBanSection\.hidden = staffRole !== "admin"/);
  assert.match(server, /if \(action\.startsWith\("admin_owner_"\)\) \{\s*adminOnly\(\)/);
  assert.match(server, /if \(action === "admin_set_role"\) \{\s*adminOnly\(\)/);
});
