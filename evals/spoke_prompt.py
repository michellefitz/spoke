"""Rebuilds Spoke's live prompt by reading TaskParser.swift.

The point of this file: an eval that grades a *copy* of the prompt tells you
nothing once the app's prompt changes. Everything here is extracted from the
Swift source at run time, so the evals always test what actually ships. If
the extraction can't find what it expects, it raises rather than quietly
falling back to something stale.
"""

from __future__ import annotations

import datetime as _dt
import os
import re

SWIFT_SOURCE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Spoke", "Services", "TaskParser.swift",
)

# Mirrors TagStore.defaultTags.
DEFAULT_TAGS = ["personal", "work", "shopping", "health", "finance"]


# ── Swift multiline string handling ──────────────────────────────────────────

def _trailing_backslashes(line: str) -> int:
    n = 0
    for ch in reversed(line):
        if ch == "\\":
            n += 1
        else:
            break
    return n


def _join_swift_lines(raw: str) -> str:
    """Swift's `\\` at end of line suppresses the newline."""
    out = []
    for line in raw.split("\n"):
        stripped = line.rstrip()
        if _trailing_backslashes(stripped) % 2 == 1:
            out.append(stripped[:-1])
        else:
            out.append(stripped + "\n")
    return "".join(out)


def _unescape(text: str) -> str:
    """Resolve Swift escapes. Runs *after* interpolations are substituted, so
    `\\(` never reaches here."""
    out, i = [], 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            if nxt == "\\":
                out.append("\\")
                i += 2
                continue
            if nxt == '"':
                out.append('"')
                i += 2
                continue
        out.append(ch)
        i += 1
    return "".join(out)


def _extract_block(source: str, anchor: str) -> str:
    """The first `\"\"\"` block after `anchor`, dedented."""
    start = source.find(anchor)
    if start == -1:
        raise RuntimeError(f"Prompt extraction failed: no {anchor!r} in TaskParser.swift")
    open_q = source.find('"""', start)
    close_q = source.find('"""', open_q + 3)
    if open_q == -1 or close_q == -1:
        raise RuntimeError(f"Prompt extraction failed: no triple-quoted block after {anchor!r}")

    body = source[open_q + 3:close_q]
    body = body.lstrip("\n")
    lines = body.split("\n")
    # Swift dedents relative to the closing delimiter's indentation.
    closing_indent = len(lines[-1]) - len(lines[-1].lstrip()) if lines else 0
    dedented = [ln[closing_indent:] if len(ln) >= closing_indent else ln.lstrip() for ln in lines]
    return "\n".join(dedented).rstrip()


# ── Pieces the Swift code interpolates ───────────────────────────────────────

def date_context(today: _dt.date) -> str:
    """Mirrors TaskParser.dateContext() with a pinned date."""
    entries = []
    for offset in range(14):
        d = today + _dt.timedelta(days=offset)
        label = " (today)" if offset == 0 else (" (tomorrow)" if offset == 1 else "")
        entries.append(f"{d.strftime('%A')} = {d.isoformat()}{label}")
    return (
        f"Today is {today.strftime('%A')}, {today.isoformat()}. "
        "Resolve day names to dates using EXACTLY this table — a task due on a "
        "named day gets THAT day's date, never the day before or after: "
        + "; ".join(entries)
        + "."
    )


def tag_instruction(tags=DEFAULT_TAGS) -> str:
    if not tags:
        return 'Do not include a "tag" field.'
    return (
        "If the task clearly belongs to one of these categories, include it as "
        f'"tag": {", ".join(tags)}. Omit "tag" if unsure.'
    )


def task_list_block(tasks) -> str:
    if not tasks:
        return "There are no existing tasks."
    items = []
    for t in tasks:
        parts = [f'"{t["title"]}"']
        desc = t.get("description")
        if desc:
            parts.append("desc: " + desc[:80].replace("\n", " "))
        items.append("- " + " | ".join(parts))
    return "Existing tasks:\n" + "\n".join(items)


def event_list_block(events) -> str:
    if not events:
        return "There are no upcoming calendar events."
    items = []
    for e in events:
        start = _dt.datetime.fromisoformat(e["start"])
        if e.get("all_day"):
            when = f"{start.strftime('%a %Y-%m-%d')} all day"
        else:
            end = _dt.datetime.fromisoformat(e["end"])
            when = f"{start.strftime('%a %Y-%m-%d')} {start.strftime('%H:%M')}–{end.strftime('%H:%M')}"
        items.append(f'- "{e["title"]}" {when}')
    return (
        'Upcoming calendar events (read-only list — change them ONLY via "edit-event"):\n'
        + "\n".join(items)
    )


# ── Assembly ─────────────────────────────────────────────────────────────────

def _source() -> str:
    with open(SWIFT_SOURCE, encoding="utf-8") as fh:
        return fh.read()


def build_assistant_prompt(today: _dt.date, tasks=None, events=None, tags=DEFAULT_TAGS) -> str:
    """The system prompt parseAssistant() sends — the app's main path."""
    src = _source()
    system_raw = _extract_block(src, "static func parseAssistant")
    rules_raw = _extract_block(src, "private static func actionRules")

    rules = _join_swift_lines(rules_raw).replace(
        "\\(tagInstruction)", tag_instruction(tags)
    )

    text = _join_swift_lines(system_raw)
    substitutions = {
        "\\(today)": date_context(today),
        "\\(taskList)": task_list_block(tasks or []),
        "\\(eventList)": event_list_block(events or []),
        "\\(actionRules(tagInstruction: tagInstruction))": rules,
    }
    for token, value in substitutions.items():
        text = text.replace(token, value)

    text = _unescape(text)

    leftover = re.search(r"\\\([^)]*\)", text)
    if leftover:
        raise RuntimeError(
            f"Prompt extraction failed: unhandled interpolation {leftover.group(0)!r}. "
            "TaskParser.swift changed — teach spoke_prompt.py about it before trusting a run."
        )
    return text


def build_create_prompt(today: _dt.date, tags=DEFAULT_TAGS) -> str:
    """The onboarding-only parse() prompt."""
    src = _source()
    raw = _extract_block(src, "static func parse(transcript: String)")
    text = _join_swift_lines(raw)
    text = text.replace("\\(today)", date_context(today))
    text = text.replace("\\(tagInstruction)", tag_instruction(tags))
    text = _unescape(text)
    leftover = re.search(r"\\\([^)]*\)", text)
    if leftover:
        raise RuntimeError(f"Unhandled interpolation {leftover.group(0)!r} in parse()")
    return text


if __name__ == "__main__":
    print(build_assistant_prompt(_dt.date(2026, 8, 12)))
