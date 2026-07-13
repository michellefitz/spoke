# Spoke backlog

Ideas parked for later — not committed work.

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

Three-tier interaction prototyped in an HTML mock (see Claude session):
silent quick-add with toast → braindump summary in a half sheet behind the orb
(pinned CTAs, scrollable body, preview capped at 3 rows + "+N more") → one
clarifying question when ambiguous. Maps to SwiftUI as
`.presentationDetents([.fraction(0.78)])` + `safeAreaInset` action row, and a
`remarks`/`questions` field added to `parseUnified` so the model picks the tier.
