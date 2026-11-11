import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const edge = fs.readFileSync(path.join(root, 'supabase/functions/send-message/index.ts'), 'utf8');

test('Voice Rooms is available as a home-screen app and has all room controls', () => {
  assert.match(html, /data-app="voice"/);
  assert.match(html, /id="win-voice"/);
  assert.match(html, /id="voice-create-form"/);
  assert.match(html, /id="voice-room-capacity"/);
  assert.match(html, /id="voice-participants"/);
  assert.match(html, /id="voice-mic-toggle"/);
  assert.match(html, /id="voice-deafen-toggle"/);
  assert.match(html, /id="voice-leave"/);
  assert.match(html, /id="voice-chat-form"/);
  assert.match(html, /id="voice-chat-messages"/);
  assert.match(html, /id="voice-chat-input"/);
});

test('Voice Rooms capacity selector offers 2 through 20 participants', () => {
  for (let capacity = 2; capacity <= 20; capacity += 1) {
    assert.match(html, new RegExp(`<option value="${capacity}"`));
  }
  assert.match(edge, /requestedCapacity < VOICE_MIN_ROOM_CAPACITY \|\| requestedCapacity > VOICE_MAX_ROOM_CAPACITY/);
  assert.match(edge, /const VOICE_MAX_ROOM_CAPACITY = 20/);
  assert.match(edge, /maxParticipants:\s*requestedCapacity/);
});

test('Voice Rooms uses the existing send-message Edge Function and LiveKit browser SDK', () => {
  assert.match(html, /livekit-client@2\.23\.0/);
  assert.match(html, /supabaseFunctionsUrl}\/send-message/);
  assert.match(html, /action: `voice_\$\{action\}`/);
  assert.match(html, /room\.connect\(credentials\.serverUrl, credentials\.token\)/);
  assert.match(html, /RoomEvent\.DataReceived/);
  assert.match(html, /publishData\(payload, \{ reliable: true \}\)/);
  assert.doesNotMatch(html, /LIVEKIT_API_SECRET/);
});

test('Voice room chat is limited to 500 characters and displays remote sender names as text', () => {
  assert.match(html, /maxlength="500"/);
  assert.match(html, /message\.length > 500/);
  assert.match(html, /body\.textContent = message/);
  assert.match(edge, /canPublishData:\s*true/);
});

test('Only the authenticated room creator can kick another participant', () => {
  assert.match(edge, /action === "voice_kick"/);
  assert.match(edge, /createdBy\.toLowerCase\(\) !== username\.toLowerCase\(\)/);
  assert.match(edge, /service\.removeParticipant\(roomName, participantIdentity\)/);
  assert.match(edge, /service\.updateRoomMetadata\(roomName/);
  assert.match(edge, /kickedUsers\.includes\(username\.toLowerCase\(\)\)/);
  assert.match(edge, /"voice_kick"/);
  assert.match(html, /voiceRequest\("kick", \{ roomName: voiceState\.roomName, participantIdentity: identity \}\)/);
  assert.match(html, /voiceState\.isOwner && !isLocal/);
});

test('Existing send-message backend authenticates and routes Voice Rooms actions', () => {
  assert.match(edge, /AccessToken, RoomServiceClient/);
  assert.match(edge, /body\.p_username/);
  assert.match(edge, /body\.p_password/);
  assert.match(edge, /voice_list/);
  assert.match(edge, /voice_create/);
  assert.match(edge, /voice_token/);
  assert.match(edge, /new AccessToken\(LIVEKIT_API_KEY, LIVEKIT_API_SECRET/);
  assert.match(edge, /roomJoin:\s*true/);
});
