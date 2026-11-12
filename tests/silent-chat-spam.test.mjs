import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const edge = await readFile(new URL("../supabase/functions/send-message/index.ts", import.meta.url), "utf8");

function sectionBetween(source, start, end) {
  const startAt = source.indexOf(start);
  assert.notEqual(startAt, -1, `missing section start: ${start}`);
  const endAt = source.indexOf(end, startAt + start.length);
  assert.notEqual(endAt, -1, `missing section end: ${end}`);
  return source.slice(startAt, endAt);
}

test("silent drops return HTTP 200 success without an error field", () => {
  assert.match(edge, /const silentlyDrop = \(\) => json\(\{ ok: true, silent: true \}\);/);
});

test("chat IP gate runs before authentication and persistent database rate limiting", () => {
  const requestPath = sectionBetween(edge, "const isPlainChatSend =", "const loginRes = await fetch");
  assert.match(requestPath, /if \(!localIpAllowed\(ipSubject\)\) return silentlyDrop\(\);/);
  assert.match(requestPath, /rateLimitAllowed\(ipSubject, "send_message_endpoint", 300, 60\)/);
  assert.ok(requestPath.indexOf("localIpAllowed") < requestPath.indexOf("rateLimitAllowed"));
});

test("account and chat-message rate limits silently drop ordinary chat sends", () => {
  assert.match(edge, /if \(!\(await rateLimitAllowed\(`account:\$\{realName\.toLowerCase\(\)\}`, "hbu_endpoint", 240, 60\)\)\) return silentlyDrop\(\);/);
  assert.match(edge, /if \(!allowed && isPlainChatSend\) return silentlyDrop\(\);/);
});

test("spam detection silences repeat/rapid spam without writing extra database rows", () => {
  const spam = sectionBetween(edge, "async function spamCheck(", "// Cheap per-instance IP gate");
  assert.match(spam, /return true;/);
  assert.match(spam, /spamSilencedUntil\.set\(key, now \+ SPAM_SILENCE_MS\);/);
  assert.doesNotMatch(spam, /\bdb\s*\(/);
  assert.doesNotMatch(spam, /\blog\s*\(/);
  assert.doesNotMatch(spam, /\bbotPost\s*\(/);
});

test("both chat command and normal main-chat spam paths discard the message", () => {
  assert.match(edge, /if \(await spamCheck\(realName, text\)\) return silentlyDrop\(\);/);
  assert.match(edge, /if \(target === "everyone" && await spamCheck\(realName, text\)\) return silentlyDrop\(\);/);
});

test("non-chat actions retain the existing explicit rate-limit failure behavior", () => {
  assert.match(edge, /if \(!allowed\) throw new UserError\("Too many requests\. Please wait a little and try again\."/);
  assert.match(edge, /await requireRateLimit\(ipSubject, "send_message_endpoint", 600, 60\)/);
});
