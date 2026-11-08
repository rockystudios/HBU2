import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");
const loaderStart = source.indexOf("async function loadAds() {");
const loaderEnd = source.indexOf("\n    const viewportChanged", loaderStart);
assert.notEqual(loaderStart, -1);
assert.notEqual(loaderEnd, -1);
const loader = source.slice(loaderStart, loaderEnd);

async function runLoader({ phoneDevice, narrowViewport }) {
  let inserted = 0;
  const slots = [{ append: script => { inserted++; script.onload(); } }, { append: script => { inserted++; script.onload(); } }];
  const context = {
    phoneDevice,
    phoneViewport: { matches: narrowViewport },
    adsLoaded: false,
    document: {
      querySelectorAll: () => slots,
      querySelector: () => ({ hidden: true }),
      createElement: () => ({ onload: null, onerror: null, src: "" }),
    },
    window: {},
  };
  await vm.runInNewContext(`(async () => { ${loader}; await loadAds(); })()`, context);
  return inserted;
}

test("phone devices and narrow viewports do not load ad scripts", async () => {
  assert.equal(await runLoader({ phoneDevice: true, narrowViewport: false }), 0);
  assert.equal(await runLoader({ phoneDevice: false, narrowViewport: true }), 0);
  assert.match(source, /\.phone-device \.home-ad, \.phone-device \.arcade-ad \{ display: none; \}/);
});

test("desktop continues loading the existing ad placements", async () => {
  assert.equal(await runLoader({ phoneDevice: false, narrowViewport: false }), 2);
});
