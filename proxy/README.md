# spoke-proxy

A tiny Cloudflare Worker that keeps the Deepgram and Anthropic API keys off
the phone. The app authenticates to it with a shared secret; the worker mints
short-lived Deepgram tokens (the app still streams audio to Deepgram
directly, so there's no added latency) and forwards parsing calls to
Anthropic with the model and token budget pinned server-side.

## Deploy (~15 minutes, free tier is fine)

1. Create a Cloudflare account at dash.cloudflare.com (free plan).
2. On your Mac, from this `proxy/` directory:

   ```sh
   npx wrangler login          # opens the browser to authorize
   openssl rand -hex 32        # copy the output — this is your app secret
   npx wrangler secret put APP_SECRET         # paste the secret
   npx wrangler secret put DEEPGRAM_API_KEY   # from console.deepgram.com
   npx wrangler secret put ANTHROPIC_API_KEY  # from console.anthropic.com
   npx wrangler deploy
   ```

   Deploy prints your URL, e.g. `https://spoke-proxy.<your-subdomain>.workers.dev`.

3. Smoke test (expect a JSON Claude response):

   ```sh
   curl -s https://spoke-proxy.<you>.workers.dev/v1/parse \
     -H "x-spoke-key: <your app secret>" \
     -H "content-type: application/json" \
     -d '{"system":"Reply with the word ok.","user":"hi"}'
   ```

4. In your local `Config.swift`, set:

   ```swift
   static let proxyBaseURL = "https://spoke-proxy.<you>.workers.dev"
   static let proxySecret  = "<your app secret>"
   ```

   With `proxyBaseURL` empty the app falls back to calling the APIs directly
   using the old `anthropicAPIKey`/`deepgramAPIKey` values — dev convenience
   only; ship builds must always set the proxy.

## Keep the blast radius small

- Set spend caps in both the Anthropic and Deepgram dashboards — the real
  safety net.
- The shared secret can still be extracted from the app binary; it gates
  casual abuse, not a determined attacker. Rotate it (`wrangler secret put
  APP_SECRET` + app update) if usage looks weird.
- Worth doing later: Apple App Attest so only genuine installs of Spoke can
  call the worker at all.
- Watch usage: `npx wrangler tail` streams live logs.
