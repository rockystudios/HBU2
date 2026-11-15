const SUPABASE_ORIGIN = "https://xvkjvuxhawlljakfkllu.supabase.co";

const ALLOWED_ORIGINS = new Set([
  "https://rockystudios.github.io",
  "http://hbu2.s3-website.us-east-2.amazonaws.com",
]);

const CORS_HEADERS = {
  "Access-Control-Allow-Methods": "GET, POST, PATCH, PUT, DELETE, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-hbu-device-id, prefer, range",
  "Access-Control-Expose-Headers": "content-range, x-hbu-request-id",
  "Access-Control-Max-Age": "86400",
  "Vary": "Origin",
};

const ROUTE_LIMITS = [
  { match: /\/functions\/v1\/send-message\?action=image_challenge(?:&|$)/, name: "image_challenge", ip: 20, device: 10, window: 60 },
  { match: /\/rest\/v1\/rpc\/hbu_login$/, name: "login", ip: 20, device: 5, window: 900 },
  { match: /\/rest\/v1\/rpc\/hbu_signup$/, name: "signup", ip: 10, device: 3, window: 3600 },
  { match: /\/rest\/v1\/rpc\//, name: "rpc", ip: 60, device: 20, window: 60 },
  { match: /\/functions\/v1\/send-message$/, name: "function", ip: 60, device: 20, window: 60 },
  { match: /\/rest\/v1\//, name: "rest", ip: 120, device: 40, window: 60 },
];

function json(body, status, origin) {
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    ...CORS_HEADERS,
  });
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
  }
  return new Response(JSON.stringify(body), { status, headers });
}

function getRouteLimit(pathAndQuery, body) {
  if (pathAndQuery.startsWith("/functions/v1/send-message") && body) {
    try {
      const action = JSON.parse(new TextDecoder().decode(body)).action;
      if (action === "login_image") {
        return { name: "login", ip: 120, device: 10, window: 900 };
      }
      if (action === "signup_image") {
        return { name: "signup", ip: 60, device: 5, window: 3600 };
      }
    } catch {
      // Let the upstream function return its normal malformed-body response.
    }
  }
  return ROUTE_LIMITS.find((rule) => rule.match.test(pathAndQuery)) ?? {
    name: "default",
    ip: 60,
    device: 20,
    window: 60,
  };
}

function validApiPath(pathname) {
  return pathname.startsWith("/rest/v1/") ||
    pathname === "/functions/v1/send-message";
}

function validDeviceId(value) {
  return typeof value === "string" && /^[a-f0-9-]{36}$/i.test(value);
}

function rateLimitedResponse(retryAfter, origin, message) {
  const response = json({
    error: message,
    retry_after_seconds: retryAfter,
  }, 429, origin);
  const headers = new Headers(response.headers);
  headers.set("Retry-After", String(retryAfter));
  return new Response(response.body, { status: 429, headers });
}

async function checkLimit(namespace, identity, route, limit, windowSeconds) {
  const id = namespace.idFromName(identity);
  const stub = namespace.get(id);
  const response = await stub.fetch("https://rate-limiter/check", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ route, limit, windowSeconds }),
  });
  if (!response.ok) {
    throw new Error(`Rate limiter unavailable (${response.status}).`);
  }
  return response.json();
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin");

    if (request.method === "OPTIONS") {
      if (!origin || !ALLOWED_ORIGINS.has(origin)) {
        return new Response(null, { status: 403 });
      }
      return new Response(null, {
        status: 204,
        headers: {
          ...CORS_HEADERS,
          "Access-Control-Allow-Origin": origin,
        },
      });
    }

    // CORS is a browser-origin gate, not authentication; non-browser clients
    // can forge Origin. Supabase RLS and grants remain mandatory.
    if (!origin || !ALLOWED_ORIGINS.has(origin)) {
      return json({ error: "HBU2 website origin is not allowed." }, 403, null);
    }

    if (!validApiPath(url.pathname)) {
      return json({ error: "Gateway route not found." }, 404, origin);
    }

    if (!["GET", "POST", "PATCH", "PUT", "DELETE", "HEAD"].includes(request.method)) {
      return json({ error: "Method not allowed." }, 405, origin);
    }

    if (!request.headers.get("apikey")) {
      return json({ error: "Missing Supabase publishable API key." }, 401, origin);
    }

    const maxBodyBytes = 256 * 1024;
    const declaredLength = Number(request.headers.get("Content-Length") || 0);
    if (Number.isFinite(declaredLength) && declaredLength > maxBodyBytes) {
      return json({ error: "Request body is too large." }, 413, origin);
    }

    let body;
    if (request.method !== "GET" && request.method !== "HEAD") {
      body = await request.arrayBuffer();
      if (body.byteLength > maxBodyBytes) {
        return json({ error: "Request body is too large." }, 413, origin);
      }
    }

    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    const deviceHeader = request.headers.get("X-HBU-Device-ID");
    const deviceId = validDeviceId(deviceHeader) ? deviceHeader.toLowerCase() : null;
    const route = getRouteLimit(url.pathname + url.search, body);

    // Fail closed: if centralized limiter storage is unavailable, do not
    // forward the request to Supabase.
    try {
      const ipResult = await checkLimit(
        env.HBU_RATE_LIMITER,
        `ip:${ip}`,
        route.name,
        route.ip,
        route.window,
      );
      if (!ipResult.allowed) {
        return rateLimitedResponse(ipResult.retryAfter, origin, "Network request limit reached. Please wait.");
      }

      if (deviceId) {
        const deviceResult = await checkLimit(
          env.HBU_RATE_LIMITER,
          `device:${deviceId}`,
          route.name,
          route.device,
          route.window,
        );
        if (!deviceResult.allowed) {
          return rateLimitedResponse(deviceResult.retryAfter, origin, "Device request limit reached. Please wait.");
        }
      }
    } catch (error) {
      console.error("HBU2 rate limiter failed closed:", error);
      return json({ error: "HBU2 security checks are temporarily unavailable. Please retry shortly." }, 503, origin);
    }

    const upstreamUrl = new URL(url.pathname + url.search, SUPABASE_ORIGIN);
    const headers = new Headers(request.headers);
    headers.delete("host");
    headers.delete("x-hbu-device-id");
    headers.delete("cf-connecting-ip");
    headers.delete("x-forwarded-for");

    let upstream;
    try {
      upstream = await fetch(upstreamUrl, {
        method: request.method,
        headers,
        body,
        redirect: "manual",
      });
    } catch (error) {
      console.error("Supabase upstream request failed:", error);
      return json({ error: "The HBU2 service is temporarily unavailable." }, 502, origin);
    }

    const responseHeaders = new Headers(upstream.headers);
    responseHeaders.set("Access-Control-Allow-Origin", origin);
    for (const [key, value] of Object.entries(CORS_HEADERS)) {
      responseHeaders.set(key, value);
    }
    responseHeaders.set("Vary", "Origin");
    responseHeaders.set("Cache-Control", "no-store");
    responseHeaders.set("X-HBU-Gateway", "active");

    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders,
    });
  },
};

export class HbuRateLimiter {
  constructor(ctx) {
    this.ctx = ctx;
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS rate_buckets (
        bucket_key TEXT PRIMARY KEY,
        request_count INTEGER NOT NULL,
        reset_at INTEGER NOT NULL
      )
    `);
  }

  async fetch(request) {
    if (new URL(request.url).pathname !== "/check" || request.method !== "POST") {
      return new Response("Not found", { status: 404 });
    }

    const input = await request.json();
    const route = input?.route;
    const limit = input?.limit;
    const windowSeconds = input?.windowSeconds;

    if (
      typeof route !== "string" ||
      !Number.isInteger(limit) || limit < 1 ||
      !Number.isInteger(windowSeconds) || windowSeconds < 1
    ) {
      return Response.json({ error: "Invalid rate-limit request." }, { status: 400 });
    }

    const now = Math.floor(Date.now() / 1000);
    const bucketKey = `${route}:${Math.floor(now / windowSeconds)}`;
    const rows = this.ctx.storage.sql.exec(
      "SELECT request_count FROM rate_buckets WHERE bucket_key = ?",
      bucketKey,
    ).toArray();
    const count = rows.length ? Number(rows[0].request_count) : 0;

    if (count >= limit) {
      const retryAfter = Math.max(1, windowSeconds - (now % windowSeconds));
      return Response.json({ allowed: false, retryAfter });
    }

    this.ctx.storage.sql.exec(
      `INSERT INTO rate_buckets (bucket_key, request_count, reset_at)
       VALUES (?, 1, ?)
       ON CONFLICT(bucket_key) DO UPDATE SET request_count = request_count + 1`,
      bucketKey,
      now + windowSeconds,
    );

    if (now % 60 === 0) {
      this.ctx.storage.sql.exec(
        "DELETE FROM rate_buckets WHERE reset_at < ?",
        now - 3600,
      );
    }

    return Response.json({ allowed: true, retryAfter: 0 });
  }
}
