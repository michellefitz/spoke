# Spoke evals

Automated checks on the thing most likely to break quietly: what the model
does with what you said.

```sh
export SPOKE_EVAL_API_KEY=sk-ant-...   # ANTHROPIC_API_KEY also works

python3 evals/run.py                      # everything
python3 evals/run.py --only dates edits   # one or more categories, or a case id
python3 evals/run.py --repeat 3           # same case 3× — catches flaky passes
python3 evals/run.py --manual > sheet.md  # checklist for testing by hand
```

Exit code is 0 only if every selected case passes, so it can gate a change.

## The one design decision worth knowing

**The prompt is read out of `TaskParser.swift` at run time**, not copied here.
`spoke_prompt.py` locates the `parseAssistant` and `actionRules` string
blocks, resolves Swift's line continuations and escapes, and substitutes the
same interpolations the app does. If it meets an interpolation it doesn't
recognise it raises rather than carrying on.

This matters more than it sounds. The previous eval run in this folder
(`eval-run-1-*`) graded a *pasted copy* of the prompt that had already drifted
— no weekday table, no `this-week` bucket rule, a different date line. It
scored 29/30 while testing something the app never sends. An eval that can
drift from the system it grades is worse than no eval, because it produces
confidence instead of information.

The cost of this choice: renaming `actionRules` or restructuring those string
literals breaks extraction. That's deliberate — a loud break beats a silent
lie.

## Fixed clock

Everything is pinned to **Wednesday 12 August 2026** (`scenarios.TODAY`), so
"Friday" always means `2026-08-14` and date assertions can be exact. Change
the date and every date expectation in `scenarios.py` has to move with it.

## Adding a case

Append to `SCENARIOS` in `scenarios.py`:

```python
dict(
    id="scope-04", category="deadline-scope",
    why="Explains what breaks if this fails — read when a failure looks pedantic.",
    transcript="what you'd actually say out loud",
    tasks=TASKS_TYPICAL,          # optional: what's already on the list
    events=EVENTS_TYPICAL,        # optional: what's already on the calendar
    expect=dict(n_actions=2, deadline_of={"milk": "2026-08-14"},
                no_deadline=["dentist"]),
),
```

Assert on **properties, not exact wording**. `titles_include=["dentist"]`
survives a reasonable rephrase; `title == "Ring the dentist"` fails the moment
the model says "Call the dentist" instead, and you'll start ignoring failures.
The full assertion vocabulary is documented at the top of `scenarios.py`.

Write the `why` before the assertion. If you can't say what breaks for a user
when the case fails, the case is probably not worth having.

## Regressions

Model output moves around. An absolute pass rate is a poor gate; what you
actually care about is *did this change make anything worse*.

```sh
python3 evals/run.py --save baseline     # record how things stand today
# …change the prompt…
python3 evals/run.py --against baseline  # non-zero only if something regressed
```

`--against` also prints what got *fixed*, which is the honest way to judge a
prompt edit: almost every change to a prompt trades some cases for others.

## Manual passes

`--manual` prints a tickable sheet with the transcript, what to expect, and
what each case is guarding against. Use it when you change something the API
can't see — the recording flow, the confirmation sheet, how actions get
applied to the list.

## What this does not cover

- **Transcription.** Separate concern, and there's a live A/B running in the
  app for it (Settings → Recordings).
- **Anything after the parse** — applying actions, the confirmation sheet,
  calendar writes. That's what the manual sheet is for, and eventually a
  simulator UI test.
- **Prompts other than `parseAssistant`.** `parseEdit`, `resolveClarification`
  and `refineActions` have their own prompts and no coverage yet.
  `spoke_prompt.build_create_prompt` exists for the onboarding path if you
  want to start there.
# Evals

Runs the task-parser system prompt against 30 voice transcripts and scores how
many tasks come back per transcript.

## Running

```sh
export SPOKE_EVAL_API_KEY=sk-ant-...
python3 evals/run-eval.py
```

Outputs three files next to the script: `eval-run-1.csv` (with blank Pass/Fail
and Notes columns for manual scoring), `eval-run-1-raw.json`, and per-category
totals on stdout. Note that a re-run overwrites the CSV and JSON in place —
rename the previous run's files first if you want to compare.

## Why not ANTHROPIC_API_KEY?

Both names work, and the script checks `SPOKE_EVAL_API_KEY` first. But inside a
Claude Code session, `ANTHROPIC_API_KEY` is reserved for the session's own auth
and is stripped from every shell it spawns, so a key set under that name reaches
the container but never reaches this script. Setting `SPOKE_EVAL_API_KEY` in the
cloud environment settings sidesteps that — unreserved names pass through
normally. Environment settings are read at session start, so a new session is
needed after adding it.

## Results so far

`eval-run-1-summary.md` covers run 1 against `claude-haiku-4-5-20251001`:
29/30 task-count accuracy. The one miss is test 20, in the rambling category,
which split into 2 tasks where 1 was expected.
