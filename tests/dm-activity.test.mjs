import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");

function node() {
  const classes = new Set();
  return {
    children: [], dataset: {}, attributes: {},
    classList: { toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name); }, contains(name) { return classes.has(name); } },
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener(type, fn) { this[type] = fn; },
    replaceChildren(...children) { this.children = children; }
  };
}

function createContext() {
  const main = node();
  const list = node();
  const title = node();
  const badge = node();
  const context = {
    account: { username: "Alice", password: "pass" },
    currentConvo: "everyone", dmPartners: ["Bob", "Carol", "dave"], convoActivity: {}, seenAt: {},
    isBlocked: name => name.toLowerCase() === "dave",
    writeLocal: () => true,
    document: { title: "HBU", hidden: false, createElement: node, querySelector: () => badge },
    convoMain: main, dmList: list, convoTitle: title, appOpen: () => false,
    setReply() {}, messageList: { dataset: {} }, renderFriends() {}, loadMessages() {}, messageText: { focus() {} },
    Date, console
  };
  const start = source.indexOf("    const convoKey =");
  const end = source.indexOf('    const settingsLogin =', start);
  assert.ok(start >= 0 && end > start);
  vm.runInNewContext(source.slice(start, end), context);
  return { context, list };
}

test("DMs sort by latest activity; unread dots clear only when marked seen", () => {
  const { context: c, list } = createContext();
  c.recordConversationActivity("bob", { created_at: "2025-01-01T10:00:00Z", user: "Bob", message: "hi" });
  c.recordConversationActivity("CAROL", { created_at: "2025-01-01T11:00:00Z", user: "Alice", message: "hello" });
  c.mergePartners(["BOB", "carol", "Eve"]);
  c.renderConvos();
  assert.deepEqual(list.children.map(b => b.dataset.convo), [undefined, "Carol", "Bob", "Eve"]);
  const bob = list.children[2];
  assert.equal(bob.classList.contains("unread"), true);
  assert.match(bob.attributes["aria-label"], /unread/);
  assert.equal(list.children[1].classList.contains("unread"), false);
  c.openConvo("Bob");
  assert.equal(c.unreadCount("bob"), 1);
  c.markSeen("BOB");
  c.renderConvos();
  assert.equal(c.unreadCount("Bob"), 0);
  c.recordConversationActivity("bob", { created_at: "2025-01-01T12:00:00Z", user: "Bob", message: "new" });
  c.renderConvos();
  assert.equal(list.children[1].dataset.convo, "Bob");
  assert.equal(list.children[1].classList.contains("unread"), true);
  c.recordConversationActivity("bob", { created_at: "2025-01-01T09:00:00Z", user: "Alice" });
  assert.equal(c.unreadCount("Bob"), 1);
});

test("inbox uses summary and falls back to existing DM functions when unavailable", async () => {
  const { context: c } = createContext();
  let summary = true;
  const calls = [];
  c.rpc = async (name, args) => {
    calls.push(name);
    if (name === "hbu_inbox") {
      if (summary) return [{ partner: "Bob", last_at: "2025-01-01T10:00:00Z", last_user: "Bob", last_message: "hi" }];
      throw new Error("Missing inbox function");
    }
    if (name === "hbu_dm_partners") return [{ partner: "Bob" }];
    if (name === "hbu_get_dms") return args.p_other === "Bob" ? [{ created_at: "2025-01-01T10:00:00Z", user: "Bob", message: "hi" }] : [];
    throw new Error("Unexpected RPC");
  };
  const start = source.indexOf("    async function fetchInboxActivity(");
  const end = source.indexOf("    async function pollInbox()", start);
  assert.ok(start >= 0 && end > start);
  vm.runInNewContext("let inboxFallbackAt = 0;\n" + source.slice(start, end), c);
  let rows = await c.fetchInboxActivity(c.account);
  assert.equal(rows[0].partner, "Bob");
  assert.deepEqual(calls, ["hbu_inbox"]);
  calls.length = 0;
  summary = false;
  rows = await c.fetchInboxActivity(c.account);
  assert.equal(rows[0].last_user, "Bob");
  assert.ok(calls.includes("hbu_dm_partners"));
  assert.ok(calls.includes("hbu_get_dms"));
});

test("inbox polling tracks incoming and outgoing activity without marking a conversation read", async () => {
  const { context: c, list } = createContext();
  c.fetch = async () => ({ ok: false, status: 503 });
  c.supabaseMessagesUrl = "https://example.test/messages";
  c.supabaseAnonKey = "key";
  c.messageStatus = { textContent: "" };
  c.fetchInboxActivity = async () => [
    { partner: "Bob", last_at: "2025-01-01T10:00:00Z", last_user: "Bob", last_message: "hello" },
    { partner: "Carol", last_at: "2025-01-01T11:00:00Z", last_user: "Alice", last_message: "hi" }
  ];
  c.viewingConvo = () => true;
  const start = source.indexOf("    async function pollInbox()");
  const end = source.indexOf("    async function checkSpinReady()", start);
  assert.ok(start >= 0 && end > start);
  vm.runInNewContext("let inboxBusy = false, inboxBaseline = false;\n" + source.slice(start, end), c);
  await c.pollInbox();
  assert.deepEqual(list.children.map(b => b.dataset.convo), [undefined, "Carol", "Bob"]);
  assert.equal(c.unreadCount("Bob"), 1);
  assert.equal(c.unreadCount("Carol"), 0);
});
