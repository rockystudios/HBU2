import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const page = await readFile(new URL("../index.html", import.meta.url), "utf8");
const setup = await readFile(new URL("../supabase/role-editor.sql", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/dev-role.sql", import.meta.url), "utf8");

test("new and existing setups add the Dev role without staff privileges or extra commands", () => {
  for (const sql of [setup, migration]) {
    assert.match(sql, /\('dev', 'Dev', '<\/>', false, array\[\]::text\[\]\)/);
    assert.match(sql, /on conflict \(name\) do nothing/i);
  }
});

test("role editor accepts the badge and messages render role definitions as text", () => {
  assert.match(page, /id="role-new-badge"[^>]*maxlength="4"/);
  assert.match(page, /badge\.maxLength = 4/);
  assert.match(page, /check\.textContent = badge/);
  assert.match(page, /const key = .*JSON\.stringify\(roleDefs\)/);
});
