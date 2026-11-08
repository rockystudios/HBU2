import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");

test("Rewards and Profiles are permanent home-screen apps", () => {
  for (const app of ["rewards", "profiles"]) {
    assert.match(source, new RegExp(`<button class="app-icon" type="button" data-app="${app}">`));
    assert.match(source, new RegExp(`id="win-${app}" data-app="${app}"`));
  }
  const store = source.match(/const OFFICIAL_STORE = \{([\s\S]*?)\n    \};/)?.[1];
  assert.ok(store);
  assert.doesNotMatch(store, /\b(rewards|profiles)\s*:/);
  assert.match(source, /profiles: \{ open: \(\) => openProfiles\(\) \}/);
});

test("profile searches display the latest result and handle missing users", async () => {
  const start = source.indexOf("    async function fetchProfile(name)");
  const end = source.indexOf('    const soc = {', start);
  assert.ok(start !== -1 && end !== -1);
  const nodes = {};
  function node() {
    return {
      hidden: false, value: "", textContent: "", children: [], style: {},
      className: "", classList: { add() {} },
      addEventListener(type, fn) { this[type] = fn; },
      replaceChildren() { this.children = []; },
      append(...children) { this.children.push(...children); },
      prepend(...children) { this.children.unshift(...children); },
    };
  }
  for (const id of ["#profiles-login", "#profiles-search", "#profiles-result", "#profiles-status", "#profiles-username"]) nodes[id] = node();
  const account = { username: "Alice", password: "secret" };
  const context = {
    $: id => nodes[id], account, profileRequest: 0,
    walletAuth: () => ({}), loadPlates: async () => {}, loadAvatars: async () => {},
    plateByUser: { bob: "ocean" }, avatarByUser: { bob: "cat" },
    avatarNode: value => ({ avatar: value }),
    applyPlate: (entry, title, plate) => { entry.plate = plate; },
    document: { createElement: node },
    rpc: async (method, args) => {
      if (args.p_target === "Alice") await new Promise(resolve => setTimeout(resolve, 20));
      if (args.p_target === "Missing") throw new Error("That user does not exist.");
      return { username: args.p_target, followers: 3 };
    },
  };
  vm.runInNewContext(source.slice(start, end), context);
  context.openProfiles();
  assert.equal(nodes["#profiles-search"].hidden, false);
  const submit = nodes["#profiles-search"].submit;
  nodes["#profiles-username"].value = "Alice";
  const first = submit({ preventDefault() {} });
  nodes["#profiles-username"].value = "Bob";
  const second = submit({ preventDefault() {} });
  await Promise.all([first, second]);
  const result = nodes["#profiles-result"];
  assert.equal(result.hidden, false);
  assert.equal(result.children[0].textContent, "Bob");
  assert.equal(result.children[0].children[0].avatar, "cat");
  assert.equal(result.children[1].textContent, "3 followers");
  assert.equal(result.plate, "ocean");
  nodes["#profiles-username"].value = "Missing";
  await submit({ preventDefault() {} });
  assert.equal(result.hidden, true);
  assert.match(nodes["#profiles-status"].textContent, /does not exist/);
  context.account = null;
  context.openProfiles();
  assert.equal(nodes["#profiles-login"].hidden, false);
  assert.equal(nodes["#profiles-search"].hidden, true);
});
