import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");

test("verification preloads once, reuses fresh images and refreshes stale ones", async () => {
  const nodes = {};
  for (const id of ["#auth-image-check", "#auth-challenge-image", "#auth-challenge-answer", "#auth-challenge-refresh", "#auth-challenge-status", "#auth-mouse-status"]) {
    nodes[id] = { value: "", hidden: false, textContent: "", addEventListener(type, fn) { this[type] = fn; } };
  }
  const pending = [];
  const context = {
    document: { querySelector: id => nodes[id] },
    supabaseFunctionsUrl: "https://example.test/functions/v1",
    supabaseAnonKey: "test",
    authFetch: () => new Promise(resolve => pending.push(resolve)),
    console, Date
  };
  const start = source.indexOf('    const authImageCheck =');
  const end = source.indexOf("    function setAuthMode(", start);
  assert.ok(start >= 0 && end > start);
  vm.runInNewContext(source.slice(start, end), context);
  const first = context.loadImageChallenge();
  assert.equal(context.loadImageChallenge(), first);
  assert.equal(pending.length, 1);
  pending.shift()({ ok: true, json: async () => ({ id: "one", image: "c3Zn" }) });
  await first;
  assert.equal(nodes["#auth-challenge-image"].hidden, false);
  await context.loadImageChallenge();
  assert.equal(pending.length, 0);

  vm.runInNewContext("authChallengeLoadedAt = Date.now() - 240001", context);
  const expired = context.loadImageChallenge();
  assert.equal(pending.length, 1);
  const forced = context.loadImageChallenge(true);
  assert.equal(pending.length, 2);
  pending.shift()({ ok: true, json: async () => ({ id: "old", image: "b2xk" }) });
  pending.shift()({ ok: true, json: async () => ({ id: "new", image: "bmV3" }) });
  await Promise.all([expired, forced]);
  assert.equal(vm.runInNewContext("authChallengeId", context), "new");
  assert.equal(nodes["#auth-challenge-image"].src, "data:image/svg+xml;base64,bmV3");
});

test("initial chat state is set after player-app initialization", () => {
  const startup = source.indexOf("    showChat();\n    if (!account) void loadImageChallenge();");
  assert.ok(startup > source.indexOf("    const userApps = new Map();"));
  assert.match(source, /href="connection-test\.html"/);
  assert.match(source, /error\.name === "AbortError"/);
});
