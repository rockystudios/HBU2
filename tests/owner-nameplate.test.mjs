import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");
const start = source.indexOf("    function applyPlate(");
const end = source.indexOf("\n    async function loadPlates", start);
assert.ok(start !== -1 && end !== -1);
const code = source.slice(start, end);

function apply(username, plateId, catalog = []) {
  const classes = new Set();
  const entry = { classList: { add: name => classes.add(name) }, style: {} };
  const name = { style: {} };
  const context = { plateById: id => catalog.find(plate => plate.id === id) };
  vm.runInNewContext(`${code}\nthis.applyPlate = applyPlate;`, context);
  context.applyPlate(entry, name, plateId, username);
  return { classes, entry, name };
}

test("owner always gets the Matrix plate without catalog data and overrides any equipped plate", () => {
  assert.ok(apply("Rocky", undefined).classes.has("owner-matrix"));
  const result = apply("ROCKY", "purple", [{ id: "purple", bg: "purple", name_color: "pink" }]);
  assert.ok(result.classes.has("owner-matrix"));
  assert.equal(result.entry.style.background, undefined);
  assert.equal(result.name.style.color, undefined);
});

test("other users retain their selected plate", () => {
  const result = apply("player", "purple", [{ id: "purple", bg: "purple", name_color: "pink" }]);
  assert.equal(result.classes.has("owner-matrix"), false);
  assert.equal(result.entry.style.background, "purple");
  assert.equal(result.name.style.color, "pink");
});

test("all owner messages use the plate and reduced motion disables animation", () => {
  assert.match(source, /applyPlate\(entry, header\.firstElementChild && !joined \? header\.firstElementChild : null, plateByUser\[message\.user\.toLowerCase\(\)\], message\.user\)/);
  assert.match(source, /\.message-entry\.owner-matrix, \.message-entry\.own\.owner-matrix \{[^}]*background: #000;/);
  assert.match(source, /@keyframes matrix-scroll \{ from \{ background-position: 0 0; \} to \{ background-position: 0 96px; \}/);
  assert.match(source, /owner-matrix::before \{[^}]*animation: matrix-scroll 4s linear infinite;/);
  assert.match(source, /prefers-reduced-motion: reduce[^}]*owner-matrix::before \{ animation: none;/);
});
