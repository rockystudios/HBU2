import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../cloudflare/hbu2-security-gateway/src/index.js", import.meta.url), "utf8");
const edge = await readFile(new URL("../supabase/functions/send-message/index.ts", import.meta.url), "utf8");

test("Cloudflare gateway does not reject requests by website origin", () => {
  assert.doesNotMatch(worker, /ALLOWED_ORIGINS/);
  assert.doesNotMatch(worker, /HBU2 website origin is not allowed/);
  assert.match(worker, /"Access-Control-Allow-Origin": "\*"/);
  assert.match(worker, /headers\.set\("Access-Control-Allow-Origin", "\*"\)/);
});

test("send-message Edge Function does not reject requests by website origin", () => {
  assert.doesNotMatch(edge, /ALLOWED_ORIGINS/);
  assert.doesNotMatch(edge, /originDenied/);
  assert.match(edge, /"Access-Control-Allow-Origin": "\*"/);
  assert.match(edge, /headers\.set\("Access-Control-Allow-Origin", "\*"\)/);
});

test("private gateway token remains required by send-message", () => {
  assert.match(edge, /suppliedGatewayToken\.length < 40/);
  assert.match(edge, /suppliedGatewayToken !== HBU_GATEWAY_TOKEN/);
});
