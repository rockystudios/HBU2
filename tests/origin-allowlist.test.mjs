import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../supabase/functions/send-message/index.ts", import.meta.url), "utf8");

test("send-message allows only the two official HBU2 website origins", () => {
  assert.match(source, /"https:\/\/rockystudios\.github\.io"/);
  assert.match(source, /"http:\/\/hbu2\.s3-website\.us-east-2\.amazonaws\.com"/);
  assert.match(source, /if \(!origin \|\| !ALLOWED_ORIGINS\.has\(origin\)\) return originDenied\(\)/);
});

test("origin validation runs before the request handler", () => {
  const gate = source.indexOf("if (!origin || !ALLOWED_ORIGINS.has(origin)) return originDenied();");
  const handler = source.indexOf("const response = await handleRequest(req);");
  assert.notEqual(gate, -1);
  assert.notEqual(handler, -1);
  assert.ok(gate < handler, "origin gate must run before any backend request handling");
});

test("CORS reflects the exact allowed origin instead of using wildcard", () => {
  assert.match(source, /function corsForOrigin\(origin: string\)/);
  assert.match(source, /headers\.set\("Access-Control-Allow-Origin", origin\)/);
  assert.doesNotMatch(source, /"Access-Control-Allow-Origin": "\*"/);
});

test("missing and unapproved origins receive a 403 response", () => {
  assert.match(source, /if \(!origin \|\| !ALLOWED_ORIGINS\.has\(origin\)\) return originDenied\(\)/);
  assert.match(source, /status: 403/);
});
