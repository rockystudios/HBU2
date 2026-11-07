import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { stripTypeScriptTypes } from "node:module";
import vm from "node:vm";

const source = await readFile(new URL("../supabase/functions/send-message/index.ts", import.meta.url), "utf8");
const start = source.indexOf("const SPAM_FAST_MS");
const end = source.indexOf("const likeEscape", start);
const spamCode = stripTypeScriptTypes(source.slice(start, end));

function createSpamCheck() {
  let now = 0;
  const patches = [];
  class TestDate extends Date {
    static now() { return now; }
  }
  const context = {
    Date: TestDate,
    Map,
    isAdmin: () => false,
    enc: encodeURIComponent,
    db: async (path, options) => { patches.push(JSON.parse(options.body)); },
    log: async () => {},
    botPost: async () => {},
    UserError: class UserError extends Error {
      constructor(message, status) { super(message); this.status = status; }
    }
  };
  vm.runInNewContext(spamCode + "\nglobalThis.checkSpam = spamCheck;", context);
  return {
    patches,
    setTime: value => { now = value; },
    check: context.checkSpam
  };
}

test("three messages within five seconds trigger the mute, not two", async () => {
  const spam = createSpamCheck();
  await spam.check("player", "first");
  spam.setTime(2000);
  await spam.check("player", "second");
  assert.equal(spam.patches.length, 0);
  spam.setTime(4000);
  await assert.rejects(spam.check("player", "third"), /muted for 5 minutes/);
  assert.equal(spam.patches.length, 1);
});

test("the fast-message threshold uses a rolling five-second window", async () => {
  const spam = createSpamCheck();
  await spam.check("player", "first");
  spam.setTime(2500);
  await spam.check("player", "second");
  spam.setTime(5001);
  await spam.check("player", "third");
  assert.equal(spam.patches.length, 0);
  spam.setTime(7499);
  await assert.rejects(spam.check("player", "fourth"), /muted for 5 minutes/);
  assert.equal(spam.patches.length, 1);
});

test("the six-messages-in-ten-seconds threshold is removed", async () => {
  assert.doesNotMatch(source, /SPAM_BURST_MS|6 messages within 10s/);
});
