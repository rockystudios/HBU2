import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
const edge = fs.readFileSync(path.join(root, "supabase/functions/send-message/index.ts"), "utf8");
const social = fs.readFileSync(path.join(root, "supabase/social.sql"), "utf8");
const devices = fs.readFileSync(path.join(root, "supabase/device-security.sql"), "utf8");

test("active-user presence is shown and periodically refreshed", () => {
  assert.match(html, /id="active-users-pill"/);
  assert.match(html, /hbu_presence_ping/);
  assert.match(devices, /create table if not exists public\.hbu_presence/i);
});

test("HBU Social includes authenticated post comments", () => {
  assert.match(html, /hbu_social_comments/);
  assert.match(html, /hbu_social_comment"/);
  assert.match(social, /create table if not exists public\.social_comments/i);
  assert.match(social, /hbu_social_comment_delete/);
});

test("chat text color is sent, persisted and rendered", () => {
  assert.match(html, /id="chat-text-color"/);
  assert.match(html, /text_color: chatTextColor/);
  assert.match(html, /select=id,user,message,text_color,created_at/);
  assert.match(edge, /text_color: \/\^#\[0-9a-fA-F\]\{6\}\$\//);
});

test("device account limit and owner device ban are database enforced", () => {
  assert.match(html, /hbuDeviceId/);
  assert.match(edge, /checkDeviceBeforeSignup/);
  assert.match(edge, /enforceDevice/);
  assert.match(devices, /used_count >= 2/);
  assert.match(devices, /hbu_owner_device_ban/);
});

test("send-message Edge Function only allows the two official origins", () => {
  assert.match(edge, /https:\/\/rockystudios\.github\.io/);
  assert.match(edge, /http:\/\/hbu2\.s3-website\.us-east-2\.amazonaws\.com/);
  assert.match(edge, /if \(!origin \|\| !ALLOWED_ORIGINS\.has\(origin\)\) return originDenied\(\)/);
});
