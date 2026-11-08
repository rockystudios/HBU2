import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, access } from "node:fs/promises";
import vm from "node:vm";

const root = new URL("../", import.meta.url);
const html = await readFile(new URL("index.html", root), "utf8");
const catalog = html.match(/const games = (\[[\s\S]*?\n    \]);/)?.[1];
assert.ok(catalog, "game catalog exists");
const games = vm.runInNewContext(catalog);
const expected = [
  "bitlife", "geodash", "hextris", "minesweeper", "stickman-hook",
  "fnaf-1", "moto-x3m-pool-party", "moto-x3m-spooky-land",
];

test("each requested game has the correct URL, a unique ID, and a local cover", async () => {
  for (const id of expected) {
    const matches = games.filter(game => game.id === id);
    assert.equal(matches.length, 1, `${id} must appear once`);
    const [game] = matches;
    assert.equal(game.url, `https://tunnle-rush-2025.github.io/projects/${id}/index.html`);
    assert.ok(game.name && game.genre && game.emoji);
    assert.equal(game.image, `assets/game-covers/${id}.svg`);
    await access(new URL(game.image, root));
  }
});

test("game cards use the existing in-page player", () => {
  assert.match(html, /card\.addEventListener\("click", \(\) => \{ location\.hash = `play\/\$\{game\.id\}`; \}\)/);
  assert.match(html, /frame\.src = game\.url/);
});
