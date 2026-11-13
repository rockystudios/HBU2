import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, access } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const html = await readFile(new URL("index.html", root), "utf8");
const game = await readFile(new URL("assets/hbu-survival.js", root), "utf8");

test("HBU Survival is registered as a native HBU app", () => {
  assert.match(html, /data-app="survival"/);
  assert.match(html, /id="win-survival" data-app="survival"/);
  assert.match(html, /survival: \{ open: \(\) => window\.HBUSurvival\?\.open\(account\) \}/);
  assert.match(html, /if \(name === "survival"\) window\.HBUSurvival\?\.close\(\)/);
  assert.match(html, /games: \["arcade", "survival",/);
  assert.match(html, /"#survival": "survival"/);
});

test("HBU Survival includes its multiplayer and playable-world controls", async () => {
  assert.match(html, /id="hbu-survival-create"/);
  assert.match(html, /id="hbu-survival-join"/);
  assert.match(html, /id="hbu-survival-canvas"/);
  assert.match(game, /channel\.subscribe/);
  assert.match(game, /presenceState/);
  assert.match(game, /event: "move"/);
  assert.match(game, /event: "collect"/);
  assert.match(game, /function generateWorld/);
  assert.match(game, /function collectResource/);
  await access(new URL("assets/hbu-survival.js", root));
});
