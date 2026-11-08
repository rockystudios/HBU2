import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const page = await readFile(new URL("../index.html", import.meta.url), "utf8");

test("offline mode cannot be entered and old offline sessions are rejected", () => {
  assert.doesNotMatch(page, /id="auth-offline"|offline:\s*true|Use offline mode/);
  assert.match(page, /typeof account\.password !== "string" \|\| account\.offline\) account = null/);
});
