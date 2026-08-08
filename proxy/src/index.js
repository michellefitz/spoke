// spoke-proxy — keeps the Deepgram and Anthropic API keys off the phone.
//
// Two endpoints, both POST, both requiring the x-spoke-key header:
//   /v1/deepgram-token  -> mints a short-lived Deepgram access token; the app
//                          connects to Deepgram's websocket directly with it.
//   /v1/parse           -> forwards {system, user} to Anthropic. Model and
//                          max_tokens are pinned here, not chosen by the client.

const ANTHROPIC_MODEL = "claude-haiku-4-5-20251001";
const ANTHROPIC_MAX_TOKENS = 800;
const MAX_PROMPT_CHARS = 32_000;
const DEEPGRAM_TOKEN_TTL_SECONDS = 60;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json(405, { error: "method not allowed" });
    }
    const key = request.headers.get("x-spoke-key");
    if (!env.APP_SECRET || key !== env.APP_SECRET) {
      return json(401, { error: "unauthorized" });
    }
    if (env.RATE_LIMITER) {
      const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
      const { success } = await env.RATE_LIMITER.limit({ key: ip });
      if (!success) return json(429, { error: "rate limited" });
    }

    const path = new URL(request.url).pathname;
    if (path === "/v1/deepgram-token") return deepgramToken(env);
    if (path === "/v1/parse") return parse(request, env);
    return json(404, { error: "not found" });
  },
};

async function deepgramToken(env) {
  const upstream = await fetch("https://api.deepgram.com/v1/auth/grant", {
    method: "POST",
    headers: {
      Authorization: `Token ${env.DEEPGRAM_API_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ ttl_seconds: DEEPGRAM_TOKEN_TTL_SECONDS }),
  });
  if (!upstream.ok) {
    console.error("deepgram grant failed", upstream.status, await upstream.text());
    return json(502, { error: "token mint failed" });
  }
  // Pass through: { access_token, expires_in }
  return new Response(upstream.body, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function parse(request, env) {
  const body = await request.json().catch(() => null);
  if (!body || typeof body.system !== "string" || typeof body.user !== "string") {
    return json(400, { error: "expected {system, user}" });
  }
  if (body.system.length + body.user.length > MAX_PROMPT_CHARS) {
    return json(413, { error: "prompt too large" });
  }

  const upstream = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: ANTHROPIC_MAX_TOKENS,
      system: body.system,
      messages: [{ role: "user", content: body.user }],
    }),
  });
  // Same response shape the app already parses.
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": "application/json" },
  });
}

function json(status, obj) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}
