import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const backend = await readFile(new URL("../supabase/functions/send-message/index.ts", import.meta.url), "utf8");
const page = await readFile(new URL("../index.html", import.meta.url), "utf8");

test("login and signup no longer require image verification", () => {
  assert.match(backend, /action === "login"\) return await loginAccount/);
  assert.match(backend, /action === "signup"\) return await signup/);
  assert.doesNotMatch(backend, /login_image|signup_image|image_challenge|verifyImageChallenge/);
  assert.doesNotMatch(page, /auth-image-check|auth-challenge-image|auth-challenge-answer|login_image|signup_image/);
  assert.match(page, /action: signupMode \? "signup" : "login"/);
});
