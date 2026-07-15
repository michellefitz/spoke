# Spoke backlog

Ideas parked for later — not committed work.

## Voice as a control surface (settings & views)

Extend voice beyond task CRUD: "group by tag", "show me work stuff", "hide
completed", "turn off due dates". Fits the product rule (talk to write, touch
to read) surprisingly well — configuring IS writing. Implementation sketch:
add a third action type ("command") to `parseAssistant`'s protocol mapping to
a small enum of app intents (sort mode, tag filter, settings toggles). Low
risk because commands are all reversible; silent tier + toast is the right
feedback ("Grouped by tag ✓").

## Time views — SHIPPED v1, remaining ideas

Weekly calendar view + week-pool shipped: `deadlineIsWeek` on SpokeTask
(stored as the week's last day), "this-week"/"next-week" in the parser
protocol, week options in the detail-view date menu, and `WeekCalendarView`
(any-day pool + per-day sections, week paging) behind a calendar button in
the header. Remaining ideas:
- Monthly overview (only if weekly proves out).
- Rearranging by voice from within the calendar ("move the boiler thing to
  Thursday") — currently voice always routes through the main screen.
- Widget treatment of week-bucket tasks (they surface on the last day of
  the week as "due today", which is defensible but unconsidered).

## Calendar integration — SHIPPED v1, remaining ideas

Read-only device-calendar (EventKit) appointments now show in the week view:
`CalendarService` wraps EKEventStore, event blocks render above tasks in each
day section (calendar-colour spine + time, no checkbox), connect card in the
calendar view, Display toggle in Settings. Google/iCloud/work calendars all
arrive via the phone's calendar accounts — deliberately no Google OAuth (weekly
re-auth while unverified + Google review before App Store made it a bad trade).
Remaining ideas:
- Feed the day's appointments into the parser context so voice can answer
  "what does Thursday look like?" and place tasks around real commitments.
- Show today's appointments in the list view header or the Today section.
- Calendar picker (choose which calendars appear) if all-calendars is noisy.
- Create events by voice ("dentist Tuesday at 3" is an appointment, not a
  task) — needs write access and a task-vs-event judgment call in the parser.

## Live transcript legibility & self-correction

The live speech-to-text caption (shown above the mic while recording) is hard to
read because it renders with no background over whatever is behind it. Two parts:

1. **Legibility (small):** give the live transcript a backing surface — a subtle
   blur/scrim capsule behind the text — so it reads over any list content.
2. **Self-correcting transcript (larger):** like recent Claude/ChatGPT voice
   modes, show what's being heard and then revise it in place as context
   improves — fixing spelling, capitalization, and mis-heard words a beat after
   they appear. The streaming STT already replaces interim segments with finals
   (`VoiceRecorder` accumulates `finalSegments` + `currentInterim`), so the
   animation hooks exist; the open question is whether to add an LLM polish pass
   over the visible transcript and whether the visual "rewrite" effect is worth
   the complexity. Needs design + latency exploration before committing.

## Voice interaction model (prototyped 2026-07-13)

Three-tier interaction prototyped in an HTML mock, then implemented in-app:
silent quick-add with toast → braindump summary in a half sheet behind the orb
(preview capped at 3 rows + "+N more") → one clarifying question when ambiguous.
Implemented as `AssistantSheetView` (custom overlay, orb stays live on top) and
`TaskParser.parseAssistant`/`resolveClarification`/`refineActions`. Remaining
from the prototype: sub-second "thinking" state on the orb, and tuning the
remark/question thresholds against real usage.
