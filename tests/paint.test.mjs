import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");
const start = source.indexOf("    function paintFloodFill(");
const end = source.indexOf("\n    function setupPaint()", start);
assert.ok(start !== -1 && end !== -1);
const context = {};
vm.runInNewContext(source.slice(start, end) + "\nthis.fill = paintFloodFill;", context);

test("fill changes only the connected region and leaves boundaries intact", () => {
  const white = [255, 255, 255, 255];
  const black = [0, 0, 0, 255];
  const image = { width: 3, height: 2, data: new Uint8ClampedArray([...white, ...black, ...white, ...white, ...black, ...white]) };
  assert.equal(context.fill(image, 0, 0, [255, 0, 0, 255]), true);
  assert.deepEqual([...image.data], [255, 0, 0, 255, ...black, ...white, 255, 0, 0, 255, ...black, ...white]);
  assert.equal(context.fill(image, 0, 0, [255, 0, 0, 255]), false);
});

test("paint exposes accessible tools and independent brush and eraser sizes", () => {
  for (const id of ["brush", "eraser", "fill", "picker", "undo", "redo", "size", "eraser-size", "clear", "save"]) {
    assert.match(source, new RegExp(`id="paint-${id}"`));
  }
  assert.match(source, /tool === "eraser" \? eraserSize\.value : size\.value/);
  assert.match(source, /aria-pressed/);
  assert.match(source, /const limit = 15/);
});
