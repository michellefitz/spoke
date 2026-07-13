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

## Time views: calendar for organising the week

A weekly view (day columns/rows showing tasks due that day) and possibly a
monthly overview. Key questions before building: is it read-only (see the
week) or a planning surface (drag tasks onto days / say "move that to
Thursday")? Voice-first answer is probably: read it on screen, rearrange it
by voice. Weekly first; monthly only if weekly proves out.

## "This week" pool — tasks with a week but no day

The real planning model isn't day-assignment: many tasks are "sometime this
week" and only get a day when reality forces one. Needs a softer deadline
notion than a date — e.g. deadline granularity (day vs week) on SpokeTask, or
a computed "this week, unscheduled" bucket. Pairs naturally with the weekly
calendar view: days across the top, an unscheduled-this-week pool underneath.
This is arguably the differentiator — most to-do apps force fake precision.

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
