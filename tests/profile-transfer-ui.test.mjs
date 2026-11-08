import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");
const start = source.indexOf("    let transferPending = false;");
const end = source.indexOf("\n    spinButton.addEventListener", start);
assert.ok(start !== -1 && end !== -1);
const handler = source.slice(start, end);

function setup(rpc) {
  const form = { addEventListener(type, fn) { this.submit = fn; }, querySelector() { return button; } };
  const target = { value: "Bob" };
  const amount = { value: "35" };
  const status = { textContent: "" };
  const button = { disabled: false };
  const nodes = { "#transfer-form": form, "#transfer-target": target, "#transfer-amount": amount, "#transfer-status": status };
  const context = {
    document: { querySelector: key => nodes[key] },
    window: { confirm: () => true },
    account: { username: "Alice", password: "secret" },
    wallet: { coins: 100 },
    walletAuth: () => ({ p_username: "Alice", p_password: "secret" }),
    renderWallet: () => {},
    refreshWallet: async () => {},
    rpc,
  };
  vm.runInNewContext(handler, context);
  return { form, target, amount, status, button, context, submit: () => form.submit({ preventDefault() {}, currentTarget: form }) };
}

test("coin transfer confirms, updates balance, and blocks duplicate submissions", async () => {
  let resolve;
  const calls = [];
  const state = setup((name, args) => {
    calls.push({ name, args });
    return new Promise(done => { resolve = done; });
  });
  const first = state.submit();
  await state.submit();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "hbu_transfer_coins");
  assert.equal(calls[0].args.p_amount, 35);
  assert.equal(calls[0].args.p_target, "Bob");
  assert.equal(state.button.disabled, true);
  resolve({ username: "Bob", amount: 35, coins: 65 });
  await first;
  assert.equal(state.context.wallet.coins, 65);
  assert.match(state.status.textContent, /Sent 35 coins to Bob/);
  assert.equal(state.button.disabled, false);
});

test("invalid amounts are rejected and errors do not claim success", async () => {
  let calls = 0;
  const state = setup(async () => { calls++; throw new Error("Not enough coins."); });
  state.amount.value = "-3";
  await state.submit();
  assert.equal(calls, 0);
  assert.match(state.status.textContent, /positive whole number/);
  state.amount.value = "35";
  await state.submit();
  assert.match(state.status.textContent, /Not enough coins/);
  assert.match(state.status.textContent, /Check your balance/);
  assert.equal(state.context.wallet.coins, 100);
});
