import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TABLE = `${SUPABASE_URL}/rest/v1/platformer_rooms`;
const cors = {
  "Access-Control-Allow-Origin": "https://rockystudios.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin"
};

function response(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" }
  });
}
function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");
}
function randomCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(bytes, b => chars[b % chars.length]).join("");
}
async function hash(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, "0")).join("");
}
async function db(path = "", init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("apikey", SERVICE_KEY);
  headers.set("Authorization", `Bearer ${SERVICE_KEY}`);
  headers.set("Content-Type", "application/json");
  const res = await fetch(TABLE + path, { ...init, headers });
  const body = await res.text();
  if (!res.ok) throw new Error(`Database request failed (${res.status}): ${body.slice(0, 300)}`);
  return body ? JSON.parse(body) : null;
}
function validLevel(level: any) {
  return level && Array.isArray(level.grid) && level.grid.length === 18 &&
    level.grid.every((row: any) => Array.isArray(row) && row.length === 32 &&
      row.every((cell: any) => Number.isInteger(cell) && cell >= 0 && cell <= 20));
}
function safeState(state: any) {
  if (!state || typeof state !== "object") return {};
  const n = (v: any, fallback = 0) => Number.isFinite(v) ? Math.max(-2000, Math.min(3000, v)) : fallback;
  return {
    x: n(state.x), y: n(state.y), vx: n(state.vx), vy: n(state.vy),
    grounded: !!state.grounded, frame: n(state.frame), level: n(state.level),
    coins: n(state.coins), finished: !!state.finished, sentAt: Date.now()
  };
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return response({ error: "Use POST." }, 405);
  const origin = req.headers.get("origin") || "";
  if (origin && origin !== "https://rockystudios.github.io") return response({ error: "Origin not allowed." }, 403);
  try {
    const input = await req.json();
    const action = String(input.action || "");
    await db("?expires_at=lt." + encodeURIComponent(new Date().toISOString()), { method: "DELETE" }).catch(() => null);
    if (action === "create") {
      if (!validLevel(input.level)) return response({ error: "Invalid level data." }, 400);
      const token = randomToken();
      let room: any = null;
      for (let attempt = 0; attempt < 5 && !room; attempt++) {
        const code = randomCode();
        const rows = await db("", {
          method: "POST",
          headers: { Prefer: "return=representation" },
          body: JSON.stringify({
            room_code: code, is_public: !!input.isPublic,
            level_name: String(input.level.name || "Custom Level").slice(0, 60),
            level_data: input.level, host_token_hash: await hash(token)
          })
        }).catch(() => null);
        if (rows?.[0]) room = rows[0];
      }
      if (!room) return response({ error: "Could not create a room. Try again." }, 503);
      return response({ roomCode: room.room_code, token, seat: "host", status: room.status, level: room.level_data });
    }
    if (action === "list") {
      const rows = await db("?select=room_code,level_name,created_at&status=eq.waiting&is_public=eq.true&guest_token_hash=is.null&expires_at=gt." + encodeURIComponent(new Date().toISOString()) + "&order=created_at.asc&limit=30");
      return response({ rooms: rows || [] });
    }
    const code = String(input.roomCode || "").toUpperCase();
    if (!/^[A-Z0-9]{6}$/.test(code)) return response({ error: "Enter a valid 6-character room code." }, 400);
    const rows = await db("?room_code=eq." + encodeURIComponent(code) + "&limit=1");
    const room = rows?.[0];
    if (!room) return response({ error: "Room not found." }, 404);
    if (action === "join") {
      if (room.status !== "waiting" || room.guest_token_hash) return response({ error: "That room is already full or started." }, 409);
      const token = randomToken();
      const updated = await db("?room_code=eq." + code + "&guest_token_hash=is.null&status=eq.waiting", {
        method: "PATCH", headers: { Prefer: "return=representation" },
        body: JSON.stringify({ guest_token_hash: await hash(token), status: "playing", guest_seen_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      });
      if (!updated?.length) return response({ error: "Someone just joined this room. Pick another." }, 409);
      return response({ roomCode: code, token, seat: "guest", status: "playing", level: room.level_data });
    }
    if (action === "sync" || action === "leave") {
      const tokenHash = await hash(String(input.token || ""));
      const seat = tokenHash === room.host_token_hash ? "host" : tokenHash === room.guest_token_hash && room.guest_token_hash ? "guest" : null;
      if (!seat) return response({ error: "Room access expired." }, 403);
      if (action === "leave") {
        await db("?room_code=eq." + code, { method: "PATCH", body: JSON.stringify({ status: "closed", updated_at: new Date().toISOString() }) });
        return response({ ok: true });
      }
      if (room.status === "closed") return response({ ended: true, reason: "The other player left." });
      const ownField = seat === "host" ? "host_state" : "guest_state";
      const otherField = seat === "host" ? "guest_state" : "host_state";
      const seenField = seat === "host" ? "host_seen_at" : "guest_seen_at";
      const patch: any = { [seenField]: new Date().toISOString(), updated_at: new Date().toISOString() };
      if (input.state) patch[ownField] = safeState(input.state);
      await db("?room_code=eq." + code, { method: "PATCH", body: JSON.stringify(patch) });
      const fresh = (await db("?room_code=eq." + code + "&limit=1"))?.[0];
      const otherSeen = fresh?.[seat === "host" ? "guest_seen_at" : "host_seen_at"];
      const otherState = fresh?.[otherField] || {};
      const otherOnline = seat === "host" ? !!fresh?.guest_token_hash : true;
      if (otherSeen && Date.now() - new Date(otherSeen).getTime() > 12000) {
        await db("?room_code=eq." + code, { method: "PATCH", body: JSON.stringify({ status: "closed", updated_at: new Date().toISOString() }) });
        return response({ ended: true, reason: "The other player disconnected." });
      }
      return response({
        ended: false, status: fresh.status, level: fresh.level_data,
        other: otherState, otherOnline,
        levelName: fresh.level_name, seat
      });
    }
    return response({ error: "Unknown action." }, 400);
  } catch (error) {
    console.error(error);
    return response({ error: "Room service error. Please try again." }, 500);
  }
});