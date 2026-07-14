# MCP connector plan — Spoke in Claude & ChatGPT

Parked plan, ready to pick up. Goal: talk to your Spoke list from wherever you
already are — "add sunscreen to my list for tomorrow" mid-research in Claude,
a full braindump in ChatGPT that lands in Spoke, "what have I got on today?"
answered without opening the app.

## Why it matters (product thesis tie-in)

General assistants parse braindumps brilliantly but have nowhere to put the
result (see marketing/POSITIONING.md). An MCP connector makes Spoke that
destination — and MCP connector directories are a distribution channel.

## The architectural shift

Spoke is currently local-only (SwiftData on device, no accounts, no server).
An MCP connector is a server Claude/ChatGPT calls, so this feature introduces
Spoke's first backend. Ship it opt-in ("Connect to Claude/ChatGPT" in
Settings); local-only stays the default.

## Architecture (v1)

One small service (Cloudflare Worker + D1 suggested — ~$0 at current scale):

1. **MCP server** (Streamable HTTP) — tools:
   - `add_tasks` — batch; fields: title, description/subtasks, deadline
     (YYYY-MM-DD | "this-week" | "next-week"), tag. Mirrors TaskParser's
     protocol so behavior matches in-app voice.
   - `list_tasks` — filters: today / this week / tag / undated / completed.
   - `update_task`, `complete_task`, `delete_task` (match by id or title).
   - `get_today` / `get_week_summary` — prose-friendly summaries so "what's
     on my plate today?" and "have I got time for X this week?" answer well.
2. **Sync API for the iOS app** — push/pull with `updatedAt` cursors.
3. **Storage** — D1 (SQLite), rows keyed by user id.

## iOS sync engine (the hard 20%)

- `SpokeTask` gains `remoteID`, `updatedAt`, and tombstones for deletes.
- Sync on app foreground + after each local mutation; pull then push;
  last-write-wins per task (single-user, low conflict risk).
- Widget freshness: WidgetCenter reload after each pull. "Open Spoke and
  everything's there" = foreground sync; consider silent push later.
- Nice touch: after a pull that added tasks, show the assistant remark toast
  ("3 tasks arrived from Claude ✓").

## Auth phases

- **v1 pairing token**: app mints a token in Settings (copy/QR); used as a
  bearer for MCP (works today in Claude Code/Desktop and ChatGPT dev-mode
  connectors) and for app sync.
- **v2 OAuth**: required for the polished claude.ai custom-connector flow and
  any public directory listing.

## Privacy & cost

- Tasks leave the device for the first time — opt-in, clearly worded; delete
  account = delete rows. Consider encryption at rest later.
- Cloudflare free tier covers this until real scale; consistent with the
  free-until-real-users stance.

## Effort estimate

- Worker + MCP tools + store: 1–2 sessions.
- iOS sync engine + settings UI + pairing: 1–2 sessions.
- OAuth + directory polish: later, when distribution justifies it.

## Open questions

- Deploy target confirmation (Cloudflare vs Supabase vs fly.io).
- Session network policy currently blocks outbound deploys — deploy from
  laptop or loosen policy for the build session.
- Whether `add_tasks` should run the dedupe/clarify logic (probably v2 —
  assistants can ask their own clarifying questions before calling).
