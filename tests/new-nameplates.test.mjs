import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const setup = await readFile(new URL("../supabase/coins.sql", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/new-nameplates.sql", import.meta.url), "utf8");
const page = await readFile(new URL("../index.html", import.meta.url), "utf8");

test("the ten new plates have matching definitions for new and existing setups", () => {
  const rows = migration.match(/^\s*\('[^\n]+$/gm);
  assert.equal(rows?.length, 10);
  const ids = new Set();
  for (const row of rows) {
    const id = row.match(/^\s*\('([^']+)'/)?.[1];
    assert.ok(id);
    ids.add(id);
    assert.ok(setup.includes(row), `setup does not match ${id}`);
  }
  assert.equal(ids.size, 10);
  assert.match(migration, /on conflict \(id\) do nothing;/);
});

test("forced catalog refresh updates rewards and chat even if the catalog was loaded", async () => {
  const start = page.indexOf("    async function loadPlates(force)");
  const end = page.indexOf("\n    function formatCountdown", start);
  assert.ok(start !== -1 && end !== -1);
  let fetches = 0;
  let renders = 0;
  let messages = 0;
  const context = {
    Date, console, platesLoadedAt: 0, plateCatalog: [{ id: "old" }], plateByUser: {},
    supabaseRestUrl: "https://example.test", supabaseAnonKey: "test",
    fetch: async () => { fetches++; return { ok: true, json: async () => [{ id: "old" }, { id: "arctic" }] }; },
    rpc: async () => [],
    renderPlates: () => { renders++; },
    drawMessages: () => { messages++; },
    lastMessagesKey: "old",
  };
  vm.runInNewContext(page.slice(start, end) + "\nthis.loadPlates = loadPlates;", context);
  await context.loadPlates(true);
  assert.equal(fetches, 1);
  assert.equal(context.plateCatalog.length, 2);
  assert.equal(renders, 1);
  assert.equal(messages, 1);
  await context.loadPlates(false);
  assert.equal(fetches, 1);
});
