import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { stripTypeScriptTypes } from "node:module";
import vm from "node:vm";

const source = (await readFile(new URL("../supabase/functions/send-message/index.ts", import.meta.url), "utf8"))
  .replace(/^import .*;\n/gm, "")
  .replace("export async function handle", "async function handle");

function createServer() {
  const calls = [];
  let resetPending = false;
  const context = {
    Deno: { env: { get: key => ({ ALTCHA_HMAC_SECRET: "test-secret", SUPABASE_URL: "https://example.test", SUPABASE_SERVICE_ROLE_KEY: "test-key" })[key] }, serve() {} },
    fetch: async (url, options) => {
      calls.push({ url, body: JSON.parse(options.body) });
      if (url.endsWith("/hbu_reset_pending")) return Response.json(resetPending);
      if (url.endsWith("/hbu_login")) return Response.json("Tester");
      if (url.endsWith("/hbu_signup")) return Response.json(null);
      throw new Error(`Unexpected request: ${url}`);
    },
    crypto, TextEncoder, Response, Request, Headers, URL, console, btoa, atob, setTimeout, clearTimeout
  };
  vm.runInNewContext(stripTypeScriptTypes(source), context);
  return { handle: context.handle, calls, setReset: value => { resetPending = value; } };
}

async function challenge(handle) {
  const res = await handle(new Request("https://example.test/?action=image_challenge", { headers: { Origin: "https://rockystudios.github.io" } }));
  assert.equal(res.status, 200);
  const data = await res.json();
  const svg = atob(data.image);
  const answer = [...svg.matchAll(/>([A-Z2-9])<\/text>/g)].map(match => match[1]).join("");
  assert.equal(answer.length, 6);
  assert.match(svg, /skewX/);
  assert.match(svg, /scale/);
  return { challenge_id: data.id, challenge_answer: answer };
}

async function submit(handle, body) {
  return handle(new Request("https://example.test/", {
    method: "POST", headers: { "Content-Type": "application/json", Origin: "https://rockystudios.github.io" }, body: JSON.stringify(body)
  }));
}

test("login checks the image before accessing the database, and rejects replay", async () => {
  const { handle, calls } = createServer();
  const image = await challenge(handle);
  const body = { action: "login_image", username: "tester", password: "password", ...image };
  const response = await submit(handle, body);
  assert.deepEqual(await response.json(), { username: "Tester" });
  assert.equal(calls.length, 2);
  const replay = await submit(handle, body);
  assert.equal(replay.status, 400);
  assert.equal(calls.length, 2);
  const wrong = await challenge(handle);
  wrong.challenge_answer = wrong.challenge_answer === "AAAAAA" ? "BBBBBB" : "AAAAAA";
  assert.equal((await submit(handle, { ...body, ...wrong })).status, 400);
  assert.equal(calls.length, 2);
  const expired = await challenge(handle);
  expired.challenge_id = `1000000000000.${expired.challenge_id.split(".").slice(1).join(".")}`;
  assert.equal((await submit(handle, { ...body, ...expired })).status, 400);
  assert.equal(calls.length, 2);
});

test("signup uses the image and returns the created username", async () => {
  const { handle, calls } = createServer();
  const image = await challenge(handle);
  const response = await submit(handle, {
    action: "signup_image", username: "tester", password: "password", ...image
  });
  assert.deepEqual(await response.json(), { ok: true, username: "tester" });
  assert.equal(calls.length, 1);
  assert.ok(calls[0].url.endsWith("/hbu_signup"));
  assert.equal(calls[0].body.p_student_id, null);
});

test("password reset is offered only after image verification", async () => {
  const { handle, calls, setReset } = createServer();
  setReset(true);
  const image = await challenge(handle);
  const response = await submit(handle, { action: "login_image", username: "tester", password: "password", ...image });
  assert.deepEqual(await response.json(), { resetPending: true });
  assert.equal(calls.length, 1);
  assert.ok(calls[0].url.endsWith("/hbu_reset_pending"));
});

test("unapproved and missing origins are rejected before database access", async () => {
  const { handle, calls } = createServer();
  const denied = await handle(new Request("https://example.test/?action=image_challenge", {
    headers: { Origin: "https://copied-hbu2.example" }
  }));
  assert.equal(denied.status, 403);
  assert.equal(calls.length, 0);

  const missing = await handle(new Request("https://example.test/?action=image_challenge"));
  assert.equal(missing.status, 403);
  assert.equal(calls.length, 0);
});

test("allowed origins receive exact-origin CORS headers on preflight", async () => {
  const { handle, calls } = createServer();
  const response = await handle(new Request("https://example.test/", {
    method: "OPTIONS",
    headers: { Origin: "http://hbu2.s3-website.us-east-2.amazonaws.com" }
  }));
  assert.equal(response.status, 204);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "http://hbu2.s3-website.us-east-2.amazonaws.com");
  assert.equal(calls.length, 0);
});
