import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");
const earlyStart = source.indexOf("    window.hbuPopunder =");
const earlyEnd = source.indexOf("\n  </script>", earlyStart);
const setupStart = source.indexOf("    function setupPopunderAds()");
const setupEnd = source.indexOf("\n    async function authFetch", setupStart);
assert.ok(earlyStart !== -1 && earlyEnd !== -1 && setupStart !== -1 && setupEnd !== -1);

function run({ enabled = false, phone = false, narrow = false, saveWorks = true, readWorks = true, popupBlocked = false } = {}) {
  let saved = enabled ? "true" : null;
  let reloads = 0;
  const scripts = [];
  const checkbox = { checked: false, addEventListener(type, fn) { this[type] = fn; } };
  const status = { textContent: "" };
  const retry = { hidden: true, addEventListener(type, fn) { this[type] = fn; } };
  const testButton = { addEventListener(type, fn) { this[type] = fn; } };
  const testStatus = { textContent: "" };
  const popup = { opener: "original" };
  const viewport = { matches: narrow, addEventListener(type, fn) { this[type] = fn; } };
  const window = {
    location: { reload() { reloads++; } },
    matchMedia: () => viewport,
    open(url, target, features) { this.opened = { url, target, features }; return popupBlocked ? null : popup; },
    addEventListener(type, fn) { this[type] = fn; },
  };
  const localStorage = {
    getItem() { if (!readWorks) throw Error("blocked"); return saved; },
    setItem(key, value) { if (!saveWorks) throw Error("blocked"); saved = value; },
  };
  const document = {
    querySelector: selector => ({ "#popunder-enabled": checkbox, "#popunder-status": status, "#popunder-retry": retry, "#popunder-test": testButton, "#popunder-test-status": testStatus })[selector],
    createElement: () => ({ setAttribute(name, value) { this[name] = value; } }),
    head: { append: script => scripts.push(script) },
  };
  const context = { window, document, localStorage, navigator: { userAgent: phone ? "iPhone" : "Desktop" }, phoneDevice: phone, phoneViewport: viewport, console: { warn() {} } };
  vm.runInNewContext(source.slice(earlyStart, earlyEnd), context);
  vm.runInNewContext(source.slice(setupStart, setupEnd), context);
  return { checkbox, status, retry, testButton, testStatus, popup, viewport, window, scripts, get reloads() { return reloads; }, setSaved(value) { saved = value; } };
}

test("ads are off by default and enabling them saves consent and reloads", () => {
  const state = run();
  assert.equal(state.scripts.length, 0);
  assert.equal(state.checkbox.checked, false);
  state.checkbox.checked = true;
  state.checkbox.change();
  assert.equal(state.reloads, 1);
  assert.equal(state.scripts.length, 0);
});

test("saved desktop consent loads one supplied script early and reports success or error", () => {
  const state = run({ enabled: true });
  assert.equal(state.scripts.length, 1);
  assert.equal(state.scripts[0].src, "https://abscloud.org/1/b36782fed419837a82d7ec0008656fb1");
  assert.equal(state.scripts[0]["data-cfasync"], "false");
  state.scripts[0].onload();
  assert.match(state.status.textContent, /behind this page/);
  state.scripts[0].onerror();
  assert.match(state.status.textContent, /Could not load/);
  assert.equal(state.retry.hidden, false);
  state.retry.click();
  assert.equal(state.reloads, 1);
  assert.equal(state.scripts.length, 1);
  state.checkbox.checked = false;
  state.checkbox.change();
  assert.equal(state.reloads, 2);
});

test("phone and narrow screen gating remains in effect and resize reloads", () => {
  const phone = run({ enabled: true, phone: true });
  assert.equal(phone.scripts.length, 0);
  assert.match(phone.status.textContent, /unavailable on phones/);
  phone.viewport.change({ matches: false });
  assert.equal(phone.reloads, 0);
  const narrow = run({ enabled: true, narrow: true });
  assert.equal(narrow.scripts.length, 0);
  narrow.viewport.change({ matches: false });
  assert.equal(narrow.reloads, 1);
  const desktop = run({ enabled: true });
  desktop.viewport.change({ matches: true });
  assert.equal(desktop.reloads, 1);
});

test("storage failures never silently enable ads and cross-tab changes reload", () => {
  const failed = run({ saveWorks: false });
  failed.checkbox.checked = true;
  failed.checkbox.change();
  assert.equal(failed.checkbox.checked, false);
  assert.equal(failed.reloads, 0);
  assert.match(failed.status.textContent, /Could not save/);
  const blocked = run({ enabled: true, readWorks: false });
  assert.equal(blocked.scripts.length, 0);
  assert.match(blocked.status.textContent, /Could not read/);
  const active = run({ enabled: true });
  active.setSaved("false");
  active.window.storage({ key: "hbu-popunder-enabled" });
  assert.equal(active.reloads, 1);
});

test("the test button opens a local non-ad window and reports blocking", () => {
  const state = run();
  state.testButton.click();
  assert.equal(state.window.opened.url, "popup-test.html");
  assert.equal(state.popup.opener, null);
  assert.match(state.testStatus.textContent, /not an ad/);
  assert.equal(state.scripts.length, 0);
  const blocked = run({ popupBlocked: true });
  blocked.testButton.click();
  assert.match(blocked.testStatus.textContent, /blocked/);
});
