import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const edge = fs.readFileSync(path.join(root, 'supabase/functions/send-message/index.ts'), 'utf8');
const sql = fs.readFileSync(path.join(root, 'supabase/role-policy-acceptance.sql'), 'utf8');

test('A promoted account is required to accept the current role policy', () => {
  assert.match(edge, /const ROLE_POLICY_VERSION = "2026-11-11-v1"/);
  assert.match(edge, /async function hasAcceptedRolePolicy/);
  assert.match(edge, /action === "admin_role_policy_status"/);
  assert.match(edge, /action === "admin_role_policy_accept"/);
  assert.match(edge, /role_policy_acceptances\?on_conflict=username/);
  assert.match(edge, /if \(next && next !== prevRole\)[\s\S]*?role_policy_acceptances/);
});

test('Pending role holders are blocked from chat, admin, and Voice Rooms Edge Function actions', () => {
  assert.match(edge, /const isRolePolicyAction = action === "admin_role_policy_status" \|\| action === "admin_role_policy_accept"/);
  assert.match(edge, /currentRole !== "user" && !\(await hasAcceptedRolePolicy\(realName, currentRole\)\)/);
  assert.match(edge, /You must read and accept the HBU Staff Abuse & Consequences Policy/);
});

test('The website displays the complete policy and requires scrolling, checkbox confirmation, and acceptance', () => {
  assert.match(html, /HBU Staff Abuse &amp; Consequences Policy|HBU Staff Abuse & Consequences Policy/);
  assert.match(html, /role-policy-scroll/);
  assert.match(html, /role-policy-confirm-checkbox/);
  assert.match(html, /Scroll through the entire policy/);
  assert.match(html, /admin_role_policy_accept/);
  for (const phrase of ['Abuse of Permissions', 'Unfair Treatment', 'Severe violations may result in immediate suspension or removal without a prior warning.', 'By accepting a staff role, you agree to follow this policy.']) {
    assert.ok(html.includes(phrase), `policy text missing: ${phrase}`);
  }
});

test('Acceptance records are private to the service role and can be safely migrated', () => {
  assert.match(sql, /create table if not exists public\.role_policy_acceptances/);
  assert.match(sql, /enable row level security/);
  assert.match(sql, /revoke all on public\.role_policy_acceptances from anon, authenticated/);
});

test('The Accept policy button enforces a five-second wait after the policy is read and checked', () => {
  assert.match(html, /let acceptReadyAt = 0/);
  assert.match(html, /acceptReadyAt = Date\.now\(\) \+ 5000/);
  assert.match(html, /Please wait \$\{remainingSeconds\}s/);
  assert.match(html, /accept\.disabled = remainingMs > 0/);
});
