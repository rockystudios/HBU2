import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const gateway = await readFile(
  new URL("../cloudflare/hbu2-security-gateway/src/index.js", import.meta.url),
  "utf8",
);

test("chat history reads bypass gateway usage buckets", () => {
  assert.ok(gateway.includes('request.method === "GET" && url.pathname === "/rest/v1/messages"'));
  assert.ok(gateway.includes('request.method === "POST" &&'));
  assert.ok(gateway.includes('/^\\/rest\\/v1\\/rpc\\/hbu_(?:inbox|dm_partners|get_dms)$/'));
  assert.ok(gateway.includes("const isMessageHistoryRead ="));
});

test("message creation and other writes remain rate-limited", () => {
  const bypass = gateway.indexOf("if (!isMessageHistoryRead) {");
  const limiter = gateway.indexOf("const ipResult = await checkLimit(", bypass);
  const upstream = gateway.indexOf("upstream = await fetch(upstreamUrl", bypass);
  assert.ok(bypass >= 0, "read-only bypass guard exists");
  assert.ok(limiter > bypass, "non-read requests still enter the rate limiter");
  assert.ok(upstream > limiter, "rate-limited requests continue to Supabase only after checks");
});
