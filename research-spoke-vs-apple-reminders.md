# Spoke vs Apple Reminders
## Competitive audit
*Compiled 16 August 2026. Companion to `research-task-management-apps.md`.*

---

## The one-paragraph verdict

Reminders is the default Spoke has to displace: free, preinstalled, synced,
deeply wired into iOS. It wins on breadth, ecosystem, and reliability
features (notifications, recurring, location, sharing). Spoke wins on the
capture moment and the planning view: nothing in Reminders — including Siri —
turns a 30-second ramble into five structured tasks, a calendar event, and a
clarifying question. Spoke should not try to out-feature Reminders; it should
stay the fastest way to get a messy day out of your head and into shape, and
adopt Reminders' table-stakes features (notifications first) only where their
absence actively breaks trust.

---

## Head to head

| Dimension | Apple Reminders | Spoke |
|---|---|---|
| Price / install | Free, preinstalled | Free (personal), needs install |
| Platforms | iPhone, iPad, Mac, Watch, web (iCloud) | iPhone only |
| Sync | iCloud, instant, free | None (single device) |
| Capture — typing | Fast, natural-language dates on one task at a time | Secondary (voice-first by design) |
| Capture — voice | Siri: one task per utterance, rigid phrasing, misfires punished | Hold-to-talk ramble → LLM parses multiple tasks, dates, tags, subtasks in one go |
| Editing by voice | No (re-dictate or type) | Conversational: "actually make that 2pm" edits the right item |
| Clarification | Never asks; guesses or fails | Asks one question when genuinely ambiguous |
| Task model | Title, notes, date/time, priority, flags, tags, subtasks, images, URLs | Title, description, deadline, "this week" fuzzy bucket, tag, subtasks |
| Fuzzy scheduling | No — a date or nothing | "This week / next week" pool, distinct from day-scheduled tasks |
| Week planning view | List/smart-list based; no week-at-a-glance | Week view: pinned pool + days, calendar events inline, past days collapse to "All done" |
| Calendar events | Separate app (Calendar shows reminders since iOS 18) | Read AND write (voice-created events, always confirmed) in the same view |
| Notifications | Rich: time, location, "when messaging", early reminders | **None yet — biggest gap** |
| Recurring tasks | Full recurrence engine | No |
| Shared lists | Yes, with assignment | No |
| Siri / system integration | Deep: Siri, widgets, lock screen, Watch, Spotlight | Widget only |
| Smart lists / filters | Rich queries (tags, dates, flags) | Tag pills, due-date grouping |
| Grocery mode | Auto-categorises grocery lists | No (subtask checklists cover some of it) |
| Privacy | On-device + iCloud, no third party | Mic + cloud LLM for parsing (on-device transcription in testing) |
| Account required | Apple ID only | None (personal build) |
| Design temperament | Utilitarian, dense, system-styled | Opinionated: calm, coral, voice-first, Simple/Organized modes |

---

## Where Reminders wins (honest list)

1. **It's already there.** Zero acquisition friction, and "good enough" for
   most people. This is the moat Spoke runs into with every potential user.
2. **Notifications.** A task manager that can't tap you on the shoulder is a
   notebook. Spoke's missing deadline notifications are the single biggest
   trust gap (already an open item).
3. **Sync and platforms.** The iPhone-only, single-device story caps Spoke at
   "companion app" until CloudKit sync exists.
4. **Reliability features accumulated over a decade:** recurrence, location
   triggers, shared lists, attachments, early reminders, templates.
5. **Siri for the trivial case.** "Remind me to take the bins out at 7" is
   genuinely faster through Siri than unlocking to any app — including Spoke.

## Where Spoke wins

1. **The braindump.** One hold-to-talk ramble becomes structured tasks with
   dates, tags, and subtasks — plus a summary sheet and a single clarifying
   question when needed. Reminders has no equivalent at any price.
2. **Conversational editing.** "Change the hair appointment to 2pm" works,
   and correctly targets a calendar event over a similarly-named task.
3. **Tasks and calendar in one plane.** The week view shows what's booked
   next to what needs doing, and voice can create events (with confirmation)
   without leaving the app. Apple splits this across two apps.
4. **Fuzzy time.** The "this week" pool matches how people actually commit to
   things. Reminders forces a date or gives you nothing.
5. **Opinionated calm.** Past days collapse to "All done · 3 tasks", free
   days say "Nothing planned" in coral only when it's today, Simple mode
   hides the machinery. Reminders is a filing cabinet; Spoke is trying to be
   a morning glance.

## What to steal (and what to skip)

**Steal, in order:**
1. **Deadline notifications** — table stakes, already on the open list.
2. **Recurring tasks** — "every Monday" is a natural voice phrase; the parser
   is well placed to catch it, and its absence surprises people.
3. **Early-reminder nudges** ("remind me the day before") — cheap once
   notifications exist, very voice-friendly.

**Skip (for now):**
- Shared lists / assignment — collaboration is a different product.
- Attachments, images, URLs — capture-by-voice rarely produces them.
- Smart-list query builder — power-user surface area that fights Simple mode.
- Grocery auto-categorisation — subtask checklists already cover the use case.

## Strategic footing

Reminders competes on *completeness*; Spoke competes on *the first ten
seconds* (capture) and *the first ten seconds of the morning* (the week
glance). The risk to watch is Apple Intelligence: if Siri gains multi-task
conversational capture into Reminders, Spoke's moat narrows to the week view
and the calendar-write flow — which argues for keeping the parser quality bar
high (evals) and the planning view genuinely better than a list. Integration
options with Reminders itself are parked in `BACKLOG.md`.
