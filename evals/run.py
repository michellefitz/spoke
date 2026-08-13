#!/usr/bin/env python3
"""Run Spoke's eval suite against the live prompt.

    export ANTHROPIC_API_KEY=sk-ant-...
    python3 evals/run.py                     # everything
    python3 evals/run.py --only dates edits  # some categories
    python3 evals/run.py --repeat 3          # flakiness check
    python3 evals/run.py --save baseline     # record current behaviour
    python3 evals/run.py --against baseline  # fail only on regressions
    python3 evals/run.py --manual > sheet.md # checklist for testing by hand

Exit code is non-zero when the run fails its gate, so it can sit in CI.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as _dt
import json
import os
import re
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import scenarios as S              # noqa: E402
import spoke_prompt                # noqa: E402

MODEL = "claude-haiku-4-5-20251001"
MAX_TOKENS = 800
RESULTS_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MAX_TITLE = 50


# ── API ──────────────────────────────────────────────────────────────────────

def call_model(system: str, user: str, api_key: str) -> str:
    payload = json.dumps({
        "model": MODEL,
        "max_tokens": MAX_TOKENS,
        "system": system,
        "messages": [{"role": "user", "content": user}],
    }).encode()
    request = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=payload,
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        body = json.loads(response.read())
    return body["content"][0]["text"]


def extract_json(text: str) -> str:
    """Mirrors TaskParser.extractJSON — strips code fences if present."""
    trimmed = text.strip()
    if trimmed.startswith("```"):
        lines = trimmed.split("\n")
        trimmed = "\n".join(lines[1:-1]).strip() or text.strip()
    return trimmed


# ── Reading actions ──────────────────────────────────────────────────────────

def kind_of(action: dict) -> str:
    return action.get("action", "create")


def label_of(action: dict) -> str:
    """What this action is 'about', for substring matching."""
    return " ".join(str(action.get(k, "")) for k in ("title", "match"))


def find(actions, needle):
    needle = needle.lower()
    for action in actions:
        if needle in label_of(action).lower():
            return action
    return None


def all_text(actions) -> str:
    parts = []
    for action in actions:
        for key in ("title", "description", "location", "match"):
            if action.get(key):
                parts.append(str(action[key]))
    return " ".join(parts)


# ── Assertions ───────────────────────────────────────────────────────────────

def check(case: dict, response: dict) -> list[str]:
    """Returns a list of failure descriptions; empty means the case passed."""
    expect = case.get("expect", {})
    actions = response.get("actions") or []
    problems = []

    def note(msg):
        problems.append(msg)

    if "n_actions" in expect and len(actions) != expect["n_actions"]:
        note(f"expected {expect['n_actions']} action(s), got {len(actions)}"
             f" [{', '.join(kind_of(a) for a in actions) or 'none'}]")

    if "kinds" in expect:
        want, got = sorted(expect["kinds"]), sorted(kind_of(a) for a in actions)
        if want != got:
            note(f"expected kinds {want}, got {got}")

    for needle in expect.get("titles_include", []):
        if not find(actions, needle):
            note(f"no action mentioning {needle!r}")

    for needle, want in expect.get("deadline_of", {}).items():
        action = find(actions, needle) if needle else (actions[0] if actions else None)
        if action is None:
            note(f"no action matching {needle!r} to check a deadline on")
            continue
        got = action.get("deadline")
        if want is None:
            if got:
                note(f"{needle!r} should have no deadline, got {got!r}")
        elif got != want:
            note(f"{needle!r} deadline expected {want!r}, got {got!r}")

    for needle in expect.get("no_deadline", []):
        action = find(actions, needle)
        if action is not None and action.get("deadline"):
            note(f"{needle!r} picked up a deadline it wasn't given ({action['deadline']!r})"
                 " — a date leaked from another task")

    for needle, want in expect.get("tag_of", {}).items():
        action = find(actions, needle) if needle else (actions[0] if actions else None)
        if action is None:
            note(f"no action matching {needle!r} to check a tag on")
        elif action.get("tag") != want:
            note(f"{needle or 'first action'} tag expected {want!r}, got {action.get('tag')!r}")

    for needle, fields in expect.get("event_of", {}).items():
        action = find(actions, needle)
        if action is None:
            note(f"no event matching {needle!r}")
            continue
        for key, want in fields.items():
            if action.get(key) != want:
                note(f"{needle!r} {key} expected {want!r}, got {action.get(key)!r}")

    if "matches" in expect:
        want = sorted(expect["matches"])
        got = sorted(a["match"] for a in actions if a.get("match"))
        if want != got:
            note(f"expected match targets {want}, got {got}")

    if "asks_question" in expect:
        asked = bool(response.get("question"))
        if asked != expect["asks_question"]:
            note("asked a question when it shouldn't have" if asked
                 else "should have asked a question and didn't")

    if "bullets_in" in expect:
        action = find(actions, expect["bullets_in"])
        if action is None:
            note(f"no action matching {expect['bullets_in']!r} to check bullets on")
        else:
            desc = action.get("description") or ""
            bullets = [ln for ln in desc.split("\n") if ln.strip().startswith("•")]
            if len(bullets) < 2:
                note(f"expected a bullet list in {expect['bullets_in']!r}, got {desc!r}")

    haystack = all_text(actions).lower()
    for fragment in expect.get("preserves", []):
        if fragment.lower() not in haystack:
            note(f"lost information: {fragment!r} appears nowhere in the result")

    cap = expect.get("max_title", DEFAULT_MAX_TITLE)
    for action in actions:
        title = action.get("title") or ""
        if len(title) > cap:
            note(f"title over {cap} chars ({len(title)}): {title!r}")

    return problems


# ── Running ──────────────────────────────────────────────────────────────────

def run_case(case: dict, api_key: str) -> dict:
    today = _dt.date.fromisoformat(S.TODAY)
    system = spoke_prompt.build_assistant_prompt(
        today, tasks=case.get("tasks"), events=case.get("events")
    )
    user = f'Transcript: "{case["transcript"]}"'
    try:
        raw = call_model(system, user, api_key)
    except urllib.error.HTTPError as err:
        return dict(id=case["id"], category=case["category"], ok=False,
                    problems=[f"API error {err.code}: {err.read().decode()[:200]}"], raw=None)
    except Exception as err:                                   # noqa: BLE001
        return dict(id=case["id"], category=case["category"], ok=False,
                    problems=[f"API call failed: {err}"], raw=None)

    try:
        response = json.loads(extract_json(raw))
    except json.JSONDecodeError:
        return dict(id=case["id"], category=case["category"], ok=False,
                    problems=["response was not valid JSON"], raw=raw)

    problems = check(case, response)
    return dict(id=case["id"], category=case["category"], ok=not problems,
                problems=problems, raw=raw, response=response)


def select(only):
    if not only:
        return list(S.SCENARIOS)
    wanted = set(only)
    picked = [c for c in S.SCENARIOS if c["category"] in wanted or c["id"] in wanted]
    if not picked:
        sys.exit(f"Nothing matches {only}. Categories: "
                 f"{', '.join(sorted(S.by_category()))}")
    return picked


# ── Reporting ────────────────────────────────────────────────────────────────

GREEN, RED, DIM, BOLD, OFF = "\033[32m", "\033[31m", "\033[2m", "\033[1m", "\033[0m"


def report(results, cases_by_id):
    by_category = {}
    for result in results:
        by_category.setdefault(result["category"], []).append(result)

    print()
    for category in sorted(by_category):
        rows = by_category[category]
        passed = sum(1 for r in rows if r["ok"])
        head = f"{BOLD}{category}{OFF}  {passed}/{len(rows)}"
        print(head if passed == len(rows) else head + f"  {RED}✗{OFF}")
        for result in rows:
            if result["ok"]:
                print(f"  {GREEN}ok{OFF}   {result['id']}")
            else:
                print(f"  {RED}FAIL{OFF} {result['id']}")
                case = cases_by_id[result["id"]]
                print(f"       {DIM}“{case['transcript'][:88]}”{OFF}")
                print(f"       {DIM}why this matters: {case['why']}{OFF}")
                for problem in result["problems"]:
                    print(f"       → {problem}")
        print()

    passed = sum(1 for r in results if r["ok"])
    total = len(results)
    pct = (100 * passed // total) if total else 0
    colour = GREEN if passed == total else RED
    print(f"{colour}{BOLD}{passed}/{total} passed ({pct}%){OFF}\n")
    return passed, total


def manual_sheet(cases):
    print("# Spoke eval — manual pass\n")
    print(f"Say each line to the app with today set to **{S.TODAY}** "
          "(a Wednesday). Tick what it got right.\n")
    for category, group in sorted(S.by_category().items()):
        print(f"\n## {category}\n")
        for case in group:
            print(f"- [ ] **{case['id']}** — say: “{case['transcript']}”")
            print(f"      - expect: {describe(case['expect'])}")
            print(f"      - watching for: {case['why']}")


def describe(expect) -> str:
    bits = []
    if "n_actions" in expect:
        bits.append(f"{expect['n_actions']} item(s)")
    if "kinds" in expect:
        bits.append("as " + ", ".join(expect["kinds"]))
    for needle, want in expect.get("deadline_of", {}).items():
        bits.append(f"{needle or 'it'} → {want}")
    for needle in expect.get("no_deadline", []):
        bits.append(f"{needle} with no date")
    for needle, fields in expect.get("event_of", {}).items():
        bits.append(f"{needle} on {fields.get('date')} at {fields.get('start')}")
    if expect.get("asks_question") is True:
        bits.append("asks a question")
    if expect.get("asks_question") is False:
        bits.append("no question")
    if "bullets_in" in expect:
        bits.append("bulleted description")
    if expect.get("preserves"):
        bits.append("keeps " + ", ".join(expect["preserves"]))
    return "; ".join(bits) or "sensible output"


# ── Entry point ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", help="categories or ids")
    parser.add_argument("--repeat", type=int, default=1,
                        help="run each case N times; a case passes only if every run passes")
    parser.add_argument("--save", metavar="NAME", help="write results as a baseline")
    parser.add_argument("--against", metavar="NAME",
                        help="fail only on cases that regressed against this baseline")
    parser.add_argument("--manual", action="store_true",
                        help="print a markdown checklist instead of calling the API")
    parser.add_argument("--jobs", type=int, default=6)
    args = parser.parse_args()

    cases = select(args.only)

    if args.manual:
        manual_sheet(cases)
        return 0

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        sys.exit("ANTHROPIC_API_KEY is not set")

    # Fail loudly if the prompt can no longer be read out of the Swift.
    spoke_prompt.build_assistant_prompt(_dt.date.fromisoformat(S.TODAY))

    expanded = [c for c in cases for _ in range(args.repeat)]
    print(f"Running {len(cases)} case(s)"
          + (f" × {args.repeat}" if args.repeat > 1 else "")
          + f" against {MODEL}…")

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        raw_results = list(pool.map(lambda c: run_case(c, api_key), expanded))

    # Collapse repeats: a case passes only if every attempt passed.
    merged = {}
    for result in raw_results:
        existing = merged.get(result["id"])
        if existing is None:
            merged[result["id"]] = result
        elif existing["ok"] and not result["ok"]:
            merged[result["id"]] = result
    results = list(merged.values())

    cases_by_id = {c["id"]: c for c in cases}
    passed, total = report(results, cases_by_id)

    out_path = os.path.join(RESULTS_DIR, "last-run.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2, ensure_ascii=False)
    print(f"{DIM}details → {out_path}{OFF}")

    if args.save:
        path = os.path.join(RESULTS_DIR, f"baseline-{args.save}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({r["id"]: r["ok"] for r in results}, fh, indent=2)
        print(f"baseline saved → {path}")
        return 0

    if args.against:
        path = os.path.join(RESULTS_DIR, f"baseline-{args.against}.json")
        if not os.path.exists(path):
            sys.exit(f"No baseline at {path}")
        with open(path, encoding="utf-8") as fh:
            baseline = json.load(fh)
        regressions = [r["id"] for r in results if baseline.get(r["id"]) and not r["ok"]]
        fixed = [r["id"] for r in results if r["ok"] and baseline.get(r["id"]) is False]
        if fixed:
            print(f"{GREEN}fixed since baseline:{OFF} {', '.join(fixed)}")
        if regressions:
            print(f"{RED}{BOLD}regressions:{OFF} {', '.join(regressions)}")
            return 1
        print(f"{GREEN}no regressions{OFF}")
        return 0

    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
