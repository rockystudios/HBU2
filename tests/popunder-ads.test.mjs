import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");
const start = source.indexOf("    function setupPopunderAds()");
const end = source.indexOf("\n    async function authFetch", start);
assert.ok(start !== -1 && end !== -1);
const setup = source.slice(start, end);

function run({ enabled = false, phone = false, narrow = false, saveWorks = true } = {}) {
  let saved = enabled;
  let reloads = 0;
  const scripts = [];
  const checkbox = { checked: false, addEventListener: (type, fn) => { checkbox[type] = fn; } };
  const status = { textContent: "" };
  const retry = { hidden: true, addEventListener: (type, fn) => { retry[type] = fn; } };
  const viewport = { matches: narrow, addEventListener: (type, fn) => { viewport[type] = fn; } };
  const window = {
    location: { reload: () => { reloads++; } },
    addEventListener: (type, fn) => { window[type] = fn; },
  };
  const document = {
    querySelector: selector => ({ "#popunder-enabled": checkbox, "#popunder-status": status, "#popunder-retry": retry })[selector],
    createElement: () => ({ setAttribute(name, value) { this[name] = value; }, remove() { this.removed = true; } }),
    head: { append: script => scripts.push(script) },
  };
  const context = {
    document, window, phoneDevice: phone, phoneViewport: viewport,
    readLocal: () => saved,
    writeLocal: (key, value) => { if (!saveWorks) return false; saved = value; return true; },
  };
  vm.runInNewContext(setup, context);
  return {
    checkbox, status, retry, viewport, window, scripts,
    get reloads() { return reloads; },
    setSaved(value) { saved = value; },
  };
}

test("popunders default to off and load only after opting in", () => {
  const state = run();
  assert.equal(state.checkbox.checked, false);
  assert.equal(state.scripts.length, 0);
  state.checkbox.checked = true;
  state.checkbox.change();
  assert.equal(state.scripts.length, 1);
  assert.equal(state.scripts[0].src, "https://abscloud.org/1/b36782fed419837a82d7ec0008656fb1");
  assert.equal(state.scripts[0]["data-cfasync"], "false");
  state.scripts[0].onerror();
  assert.match(state.status.textContent, /Could not load the ad service/);
  assert.equal(state.retry.hidden, false);
  state.retry.click();
  assert.equal(state.scripts.length, 2);
  assert.equal(state.retry.hidden, true);
  state.scripts[1].onload();
  assert.match(state.status.textContent, /behind this page/);
  state.checkbox.checked = false;
  state.checkbox.change();
  assert.equal(state.reloads, 1);
});

test("saved preference loads on desktop but not phones or narrow screens", () => {
  assert.equal(run({ enabled: true }).scripts.length, 1);
  const phone = run({ enabled: true, phone: true });
  assert.equal(phone.scripts.length, 0);
  assert.match(phone.status.textContent, /unavailable on phones/);
  const state = run({ enabled: true, narrow: true });
  assert.equal(state.scripts.length, 0);
  state.viewport.matches = false;
  state.viewport.change({ matches: false });
  assert.equal(state.scripts.length, 1);
  state.viewport.matches = true;
  state.viewport.change({ matches: true });
  assert.equal(state.reloads, 1);
});

test("failed preference saves do not activate ads and cross-tab opt-out reloads", () => {
  const failed = run({ saveWorks: false });
  failed.checkbox.checked = true;
  failed.checkbox.change();
  assert.equal(failed.checkbox.checked, false);
  assert.equal(failed.scripts.length, 0);
  assert.match(failed.status.textContent, /Could not save/);
  const active = run({ enabled: true });
  active.setSaved(false);
  active.window.storage({ key: "hbu-popunder-enabled" });
  assert.equal(active.checkbox.checked, false);
  assert.equal(active.reloads, 1);
});
