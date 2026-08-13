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
