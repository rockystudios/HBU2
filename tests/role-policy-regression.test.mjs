import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../supabase/functions/send-message/index.ts', import.meta.url), 'utf8');

test('send-message supports role policy status and acceptance actions', () => {
  assert.match(source, /const ROLE_POLICY_VERSION = "2026-11-11-v1"/);
  assert.match(source, /if \(action === "admin_role_policy_status"\)/);
  assert.match(source, /if \(action === "admin_role_policy_accept"\)/);
  assert.match(source, /role_policy_acceptances\?select=role_name,policy_version/);
});

test('policy status and acceptance are exempt from the policy acceptance gate', () => {
  assert.match(source, /const isRolePolicyAction = action === "admin_role_policy_status" \|\| action === "admin_role_policy_accept"/);
});
