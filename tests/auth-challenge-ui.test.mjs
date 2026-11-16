import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");

test("login form has no image challenge", () => {
  assert.doesNotMatch(source, /auth-image-check|auth-challenge-image|auth-challenge-answer|loadImageChallenge/);
  assert.match(source, /action: signupMode \? "signup" : "login"/);
  assert.match(source, /authForm\.addEventListener\("submit"/);
});

test("chat startup does not load an image challenge", () => {
  assert.match(source, /showChat\(\);\s*route\(\);/);
});
