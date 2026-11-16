// HBU2 browser-facing gateway hosted on the Supabase project domain.
// This avoids requiring school networks to allow the separate workers.dev hostname.
// The private gateway token is injected server-side and is never sent to browsers.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const HBU_GATEWAY_TOKEN = Deno.env.get("HBU_GATEWAY_TOKEN") ?? "";
const GATEWAY_PREFIX = "/hbu-gateway";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, PUT, DELETE, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-hbu-device-id, prefer, range, cache-control, pragma, x-requested-with",
  "Access-Control-Expose-Headers": "content-range, x-hbu-request-id",
  "Access-Control-Max-Age": "86400",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function getTargetPath(req: Request) {
  const url = new URL(req.url);
  const markerIndex = url.pathname.indexOf(GATEWAY_PREFIX);
  if (markerIndex < 0) return "";
  const suffix = url.pathname.slice(markerIndex + GATEWAY_PREFIX.length);
  return suffix + url.search;
}

function getRouteLimit(path: string, method: string, body: Uint8Array | null) {
  if (path.startsWith("/functions/v1/send-message") && body) {
    try {
      const action = JSON.parse(new TextDecoder().decode(body)).action;
      if (action === "login") return { name: "login", ip: 30, device: 5, window: 900 };
      if (action === "signup") return { name: "signup", ip: 5, device: 2, window: 3600 };
      if (action === "admin_role_policy_status" || action === "admin_role_policy_accept") {
        return { name: "role_policy", ip: 60, device: 30, window: 60 };
      }
    } catch {
      // The upstream function returns its normal malformed-body response.
    }
  }
  if (/^\/rest\/v1\/rpc\/hbu_(?:wallet|plates)$/.test(path)) return { name: "wallet_read", ip: 120, device: 60, window: 60 };
  if (/^\/rest\/v1\/rpc\/hbu_survival_sync$/.test(path)) return { name: "survival_sync", ip: 1200, device: 40, window: 60 };
  if (/^\/rest\/v1\/rpc\/hbu_(?:spin|gamble|buy_plate|equip_plate|transfer_coins)$/.test(path)) return { name: "economy_action", ip: 60, device: 20, window: 60 };
  if (/^\/rest\/v1\/rpc\/hbu_(?:inbox|dm_partners|get_dms)$/.test(path)) return { name: "dm_read", ip: 120, device: 60, window: 60 };
  if (/^\/rest\/v1\/rpc\/hbu_whats_new_(?:status|dismiss)$/.test(path)) return { name: "whats_new", ip: 120, device: 30, window: 60 };
  if (path.startsWith("/rest/v1/rpc/")) return { name: "rpc", ip: 30, device: 15, window: 60 };
  if (path.startsWith("/functions/v1/send-message")) return { name: "function", ip: 30, device: 15, window: 60 };
  if (path.startsWith("/rest/v1/")) return { name: "rest", ip: 60, device: 30, window: 60 };
  return { name: "default", ip: 30, device: 15, window: 60 };
}

async function checkLimit(subject: string, route: string, limit: number, windowSeconds: number) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/hbu_edge_rate_limit`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_subject: subject,
      p_action: route,
      p_limit: limit,
      p_window_seconds: windowSeconds,
    }),
  });
  if (!response.ok) {
    console.error("HBU2 gateway rate limiter failed:", response.status, await response.text().catch(() => ""));
    throw new Error("HBU2 security checks are temporarily unavailable.");
  }
  return await response.json() === true;
}

async function hashedIp(req: Request) {
  const raw = (req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    req.headers.get("x-forwarded-for") ??
    "unknown").split(",")[0].trim().slice(0, 100);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw));
  const hash = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `ip:${hash}`;
}

function isMessageHistoryRead(path: string, method: string) {
  return (method === "GET" && path.startsWith("/rest/v1/messages")) ||
    (method === "POST" && /^\/rest\/v1\/rpc\/hbu_(?:inbox|dm_partners|get_dms)(?:\?|$)/.test(path));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });

  if (!SUPABASE_URL || !SERVICE_KEY || HBU_GATEWAY_TOKEN.length < 40) {
    return json({ error: "HBU2 gateway is not configured. Requests are blocked until setup is complete." }, 503);
  }

  const target = getTargetPath(req);
  const pathname = target.split("?")[0];
  const validTarget = pathname.startsWith("/rest/v1/") || pathname === "/functions/v1/send-message";
  if (!validTarget) return json({ error: "Gateway route not found." }, 404);
  if (!["GET", "POST", "PATCH", "PUT", "DELETE", "HEAD"].includes(req.method)) {
    return json({ error: "Method not allowed." }, 405);
  }
  if (!req.headers.get("apikey")) return json({ error: "Missing Supabase publishable API key." }, 401);

  let body: Uint8Array | null = null;
  if (req.method !== "GET" && req.method !== "HEAD") {
    const bytes = new Uint8Array(await req.arrayBuffer());
    if (bytes.byteLength > 256 * 1024) return json({ error: "Request body is too large." }, 413);
    body = bytes;
  }

  if (!isMessageHistoryRead(target, req.method)) {
    try {
      const ip = await hashedIp(req);
      const route = getRouteLimit(target, req.method, body);
      const ipAllowed = await checkLimit(ip, route.name, route.ip, route.window);
      if (!ipAllowed) return json({ error: "Network request limit reached. Please wait." }, 429);

      const device = req.headers.get("x-hbu-device-id") ?? "";
      if (/^[a-f0-9-]{36}$/i.test(device)) {
        const deviceAllowed = await checkLimit(`device:${device.toLowerCase()}`, route.name, route.device, route.window);
        if (!deviceAllowed) return json({ error: "Device request limit reached. Please wait." }, 429);
      }
    } catch (error) {
      console.error("HBU2 gateway rate limiter failed closed:", error);
      return json({ error: "HBU2 security checks are temporarily unavailable. Please retry shortly." }, 503);
    }
  }

  const upstreamUrl = new URL(target, SUPABASE_URL);
  const headers = new Headers();
  for (const name of ["authorization", "apikey", "content-type", "prefer", "range", "accept", "x-client-info", "cache-control", "pragma"]) {
    const value = req.headers.get(name);
    if (value) headers.set(name, value);
  }
  if (pathname === "/functions/v1/send-message") {
    headers.set("x-hbu-gateway-token", HBU_GATEWAY_TOKEN);
  }

  try {
    const upstream = await fetch(upstreamUrl, {
      method: req.method,
      headers,
      body: body && req.method !== "GET" && req.method !== "HEAD" ? body : undefined,
      redirect: "manual",
    });
    const responseHeaders = new Headers(upstream.headers);
    for (const [name, value] of Object.entries(CORS_HEADERS)) responseHeaders.set(name, value);
    responseHeaders.set("Cache-Control", "no-store");
    responseHeaders.set("X-HBU-Gateway", "active");
    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders,
    });
  } catch (error) {
    console.error("HBU2 gateway upstream request failed:", error);
    return json({ error: "The HBU2 service is temporarily unavailable." }, 502);
  }
});
