import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/security-hardening.sql", import.meta.url), "utf8");
const edge = await readFile(new URL("../supabase/functions/send-message/index.ts", import.meta.url), "utf8");

test("security migration creates private persistent rate-limit and write-monitor tables", () => {
  assert.match(sql, /create table if not exists public\.hbu_edge_rate_buckets/i);
  assert.match(sql, /create table if not exists public\.hbu_write_events/i);
  assert.match(sql, /enable row level security/i);
  assert.match(sql, /revoke all on public\.hbu_edge_rate_buckets, public\.hbu_write_events from public, anon, authenticated/i);
});

test("edge rate-limit RPC is atomic and service-role-only", () => {
  assert.match(sql, /pg_advisory_xact_lock/i);
  assert.match(sql, /grant execute on function public\.hbu_edge_rate_limit\(text, text, integer, integer\) to service_role/i);
  assert.match(sql, /return current_hits <= max_hits/i);
});

test("database triggers throttle independent users per action and log successful writes", () => {
  for (const action of ["signup", "chat_message", "social_post", "social_like", "social_follow", "poll_vote", "shared_link", "app_save", "app_install"]) {
    assert.ok(sql.includes(`'${action}'`), `missing ${action} trigger policy`);
  }
  assert.match(sql, /create trigger %I before %s/i);
  assert.match(sql, /insert into public\.hbu_write_events/i);
  assert.match(sql, /hbu_guard_coin_debit/i);
  assert.match(sql, /new\.coins >= old\.coins/i);
});

test("direct browser password verification is revoked while Edge Function can still use it", () => {
  assert.match(sql, /revoke execute on function public\.hbu_login\(text, text\) from public, anon, authenticated/i);
  assert.match(sql, /grant execute on function public\.hbu_login\(text, text\) to service_role/i);
});

test("Edge Function applies persistent IP, account, signup, login-failure, and voice limits", () => {
  assert.match(edge, /hbu_edge_rate_limit/);
  assert.match(edge, /signup_ip/);
  assert.match(edge, /failed_login/);
  assert.match(edge, /hbu_endpoint/);
  assert.match(edge, /voice_create/);
  assert.match(edge, /voice_token/);
});
