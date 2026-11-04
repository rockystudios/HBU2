// Secure, centralized management API for admin.html.
// Secrets: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (Supabase Edge Function secrets).
// Optional: ADMIN_USERNAMES (comma-separated, default rocky) and ADMIN_DASHBOARD_ORIGINS.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ADMINS = (Deno.env.get("ADMIN_USERNAMES") ?? "rocky").split(",").map((name) => name.trim().toLowerCase()).filter(Boolean);
const ORIGINS = (Deno.env.get("ADMIN_DASHBOARD_ORIGINS") ?? "*").split(",").map((origin) => origin.trim()).filter(Boolean);
const MAX_BAN_HOURS = 720;
const enc = encodeURIComponent;
const corsHeaders = (request: Request) => {
  const origin = request.headers.get("origin") ?? "";
  const allowed = ORIGINS.includes("*") || ORIGINS.includes(origin);
  return {
    "Access-Control-Allow-Origin": allowed ? (ORIGINS.includes("*") ? "*" : origin) : "null",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
};
const json = (request: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(request), "Content-Type": "application/json" } });
class HttpError extends Error { status: number; constructor(message: string, status = 400) { super(message); this.status = status; } }
async function db(path: string, init: RequestInit = {}) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { ...init, headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json", ...(init.headers ?? {}) } });
  if (!response.ok) throw new Error(`Database error ${response.status}: ${await response.text()}`);
  return await response.json().catch(() => null);
}
async function audit(actor: string, action: string, target: string | null = null, details: Record<string, unknown> = {}) {
  await db("admin_audit_log", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ actor, action, target, details }) });
}
async function authenticate(username: string, password: string): Promise<string> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/hbu_login`, { method: "POST", headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" }, body: JSON.stringify({ p_username: username, p_password: password }) });
  if (!response.ok) throw new HttpError("Invalid username or password.", 401);
  const realName = await response.json();
  if (typeof realName !== "string" || !ADMINS.includes(realName.toLowerCase())) throw new HttpError("This account is not authorized to administer the site.", 403);
  return realName;
}
async function findAccount(name: string) {
  const cleaned = name.trim();
  if (!/^[A-Za-z0-9_]{3,20}$/.test(cleaned)) throw new HttpError("Enter a valid username.");
  const rows = await db(`accounts?select=username,role,banned_until,ban_reason,bot_banned&username=ilike.${enc(cleaned)}`) ?? [];
  return rows.find((row: { username: string }) => row.username.toLowerCase() === cleaned.toLowerCase());
}
const KNOWN_COMMANDS = ["warn", "sugban", "ban", "unban", "mute", "unmute", "kick", "clear", "purge", "announce", "poll", "endpoll", "lock", "unlock", "slowmode", "botban", "botunban", "banlist", "mutelist", "whois", "warns", "addword", "delword", "words", "staff", "me", "shrug", "tableflip", "unflip", "roll", "flip", "8ball", "hug", "highfive"];
async function handleAction(request: Request, actor: string, action: string, body: Record<string, unknown>) {
  if (action === "overview") {
    const [accounts, bans, staff, roleRows, recent] = await Promise.all([
      db("accounts?select=username&limit=1", { headers: { Prefer: "count=exact", Range: "0-0" } }),
      db(`accounts?select=username,banned_until,ban_reason&banned_until=gt.${enc(new Date().toISOString())}&order=banned_until.desc&limit=200`),
      db("accounts?select=username&role=not.is.null&limit=1", { headers: { Prefer: "count=exact", Range: "0-0" } }),
      db("accounts?select=role&role=not.is.null&limit=1000"),
      db("admin_audit_log?select=created_at,actor,action,target,details&order=created_at.desc&limit=8"),
    ]);
    const countFrom = (rows: unknown[]) => {
      const range = (rows as unknown as { __count?: number }[]).__count;
      return Number.isFinite(range) ? range : rows.length;
    };
    // PostgREST count is conveyed in Content-Range; use lightweight exact-count queries below if needed.
    const [accountCount, staffCount] = await Promise.all([
      db("rpc/hbu_admin_account_count", { method: "POST", body: "{}" }).catch(() => null),
      db("rpc/hbu_admin_staff_count", { method: "POST", body: "{}" }).catch(() => null),
    ]);
    return json(request, { actor, accounts: Number(accountCount) || countFrom(accounts ?? []), active_bans: (bans ?? []).length, staff: Number(staffCount) || (roleRows ?? []).length, bans: bans ?? [], recent_audit: recent ?? [] });
  }
  if (action === "users") {
    const query = typeof body.query === "string" ? body.query.trim() : "";
    const pattern = query.replace(/[%_\\]/g, "\\$&");
    const filter = pattern ? `&username=ilike.${enc(`*${pattern}*`)}` : "";
    const users = await db(`accounts?select=username,role,banned_until,ban_reason,last_seen&order=username.asc&limit=200${filter}`);
    return json(request, { users: users ?? [] });
  }
  if (action === "audit") {
    const entries = await db("admin_audit_log?select=id,created_at,actor,action,target,details&order=created_at.desc&limit=100");
    return json(request, { entries: entries ?? [] });
  }
  if (action === "roles") {
    const roles = await db("custom_roles?select=name,label,badge,staff,commands&order=name.asc").catch(() => []);
    return json(request, { roles: roles ?? [] });
  }
  if (action === "words") {
    const words = await db("banned_words?select=id,word&order=word.asc");
    return json(request, { words: words ?? [] });
  }
  if (action === "ban" || action === "unban" || action === "set_role" || action === "bot_block" || action === "bot_restore") {
    const target = await findAccount(String(body.target ?? ""));
    if (!target) throw new HttpError("That account was not found.", 404);
    if (ADMINS.includes(target.username.toLowerCase())) throw new HttpError("You cannot change an administrator account.", 403);
    if (action === "ban") {
      const hours = Math.min(MAX_BAN_HOURS, Math.max(1, Math.round(Number(body.hours)) || 24));
      const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 200) : "";
      const until = new Date(Date.now() + hours * 3600000).toISOString();
      await db(`accounts?username=eq.${enc(target.username)}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ banned_until: until, ban_reason: reason || "Broke the chat rules" }) });
      await audit(actor, "user_banned", target.username, { hours, reason: reason || "Broke the chat rules", until });
      return json(request, { ok: true });
    }
    if (action === "unban") {
      await db(`accounts?username=eq.${enc(target.username)}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ banned_until: null, ban_reason: null }) });
      await audit(actor, "user_unbanned", target.username);
      return json(request, { ok: true });
    }
    if (action === "set_role") {
      const role = typeof body.role === "string" && body.role !== "none" ? body.role : null;
      if (role) {
        const defs = await db(`custom_roles?select=name&name=eq.${enc(role)}`).catch(() => []);
        if (!defs?.length) throw new HttpError("Choose a configured role.");
      }
      await db(`accounts?username=eq.${enc(target.username)}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ role }) });
      await audit(actor, "user_role_changed", target.username, { previous_role: target.role ?? null, role });
      return json(request, { ok: true });
    }
    const blocked = action === "bot_block";
    await db(`accounts?username=eq.${enc(target.username)}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ bot_banned: blocked, bot_strikes: 0 }) });
    await audit(actor, blocked ? "mod_bot_blocked" : "mod_bot_restored", target.username);
    return json(request, { ok: true });
  }
  if (action === "word_add") {
    const word = typeof body.word === "string" ? body.word.trim().slice(0, 40) : "";
    if (!word) throw new HttpError("Enter a word first.");
    try { await db("banned_words", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ word, created_by: actor }) }); }
    catch (error) { if (String(error).includes("23505")) throw new HttpError("That word is already filtered."); throw error; }
    await audit(actor, "filter_word_added", null, { word });
    return json(request, { ok: true });
  }
  if (action === "word_delete") {
    const id = Number(body.id);
    if (!Number.isSafeInteger(id) || id <= 0) throw new HttpError("Invalid word id.");
    const removed = await db(`banned_words?id=eq.${id}&select=id,word`, { method: "DELETE", headers: { Prefer: "return=representation" } }) ?? [];
    if (!removed.length) throw new HttpError("Filtered word not found.", 404);
    await audit(actor, "filter_word_removed", null, { word: removed[0].word });
    return json(request, { ok: true });
  }
  if (action === "role_save") {
    const name = String(body.name ?? "").trim().toLowerCase();
    if (!/^[a-z0-9_-]{2,20}$/.test(name) || ["admin", "user", "none"].includes(name)) throw new HttpError("Role name must be 2–20 letters, numbers, - or _.");
    const label = String(body.label ?? "").trim().slice(0, 24) || name;
    const badge = String(body.badge ?? "").trim().slice(0, 4) || "★";
    const commands = Array.isArray(body.commands) ? [...new Set(body.commands.map(String).filter((command) => KNOWN_COMMANDS.includes(command)))] : [];
    await db("custom_roles?on_conflict=name", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=minimal" }, body: JSON.stringify({ name, label, badge, staff: body.staff === true, commands }) });
    await audit(actor, "role_saved", name, { label, staff: body.staff === true, command_count: commands.length });
    return json(request, { ok: true });
  }
  if (action === "role_delete") {
    const name = String(body.name ?? "").trim().toLowerCase();
    if (!/^[a-z0-9_-]{2,20}$/.test(name)) throw new HttpError("Invalid role name.");
    await db(`accounts?role=eq.${enc(name)}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ role: null }) });
    await db(`custom_roles?name=eq.${enc(name)}`, { method: "DELETE", headers: { Prefer: "return=minimal" } });
    await audit(actor, "role_deleted", name);
    return json(request, { ok: true });
  }
  throw new HttpError("Unknown dashboard action.");
}
const attempts = new Map<string, number[]>();
Deno.serve(async (request: Request) => {
  const cors = corsHeaders(request);
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json(request, { error: "Use POST." }, 405);
  const ip = (request.headers.get("cf-connecting-ip") ?? request.headers.get("x-forwarded-for") ?? "unknown").split(",")[0].trim().slice(0, 64);
  const now = Date.now(); const recent = (attempts.get(ip) ?? []).filter((time) => now - time < 60000);
  if (recent.length >= 30) return json(request, { error: "Too many requests. Wait a minute and try again." }, 429);
  recent.push(now); attempts.set(ip, recent);
  try {
    const body = await request.json().catch(() => null);
    if (!body || typeof body.username !== "string" || typeof body.password !== "string" || typeof body.action !== "string") throw new HttpError("Missing credentials or action.");
    const actor = await authenticate(body.username, body.password);
    return await handleAction(request, actor, body.action, body);
  } catch (error) {
    if (error instanceof HttpError) return json(request, { error: error.message }, error.status);
    console.error("admin-dashboard failed", error);
    return json(request, { error: "Admin request failed. Check the Edge Function and database setup." }, 500);
  }
});
