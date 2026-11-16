import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const gateway = await readFile(
  new URL("../cloudflare/hbu2-security-gateway/src/index.js", import.meta.url),
  "utf8",
);

test("chat history reads bypass gateway usage buckets", () => {
  assert.match(gateway, /request\.method === "GET" && url\.pathname === "\/rest\/v1\/messages"/);
  assert.match(gateway, /request\.method === "POST"[\s\S]*?hbu_\(?:inbox\|dm_partners\|get_dms\)/);
  assert.match(gateway, /if \(!isMessageHistoryRead\) \{[\s\S]*?checkLimit\(/);
});

test("message creation and other writes remain rate-limited", () => {
  assert.match(gateway, /if \(!isMessageHistoryRead\) \{[\s\S]*?checkLimit\(/);
  assert.match(gateway, /\/rest\/v1\/rpc\/hbu_\(?:inbox\|dm_partners\|get_dms\)/);
  assert.match(gateway, /\/rest\/v1\//);
});
