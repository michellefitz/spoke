#!/usr/bin/env python3
"""
Spoke Simulated User Testing
Runs several persona agents through the app, collects their feedback,
then has a PM agent synthesise everything into a prioritised product report.

Usage:
    python3 testing/simulate.py              # run all personas
    python3 testing/simulate.py --pm-only    # re-run PM synthesis on saved results
    python3 testing/simulate.py --persona 2  # run a single persona by index (0-based)

Results are saved to testing/results/  (created automatically).
"""

import anthropic
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import agent  # agent.py in the same directory

# ── Personas ──────────────────────────────────────────────────────────────────

PERSONAS = [
    {
        "name": "Alex Chen",
        "age": 34,
        "role": "Product manager at a 50-person startup",
        "personality": (
            "Efficiency-obsessed. Already uses Notion, Todoist, and a paper notebook. "
            "Skeptical of yet another task app but genuinely curious about the voice angle. "
            "Will compare everything to apps she already uses."
        ),
        "tasks": [
            "Try to create a work task using voice — say something like 'review Q2 roadmap by end of week'",
            "Create two more tasks in different categories (personal and work) using voice",
            "See if you can filter the list in any way",
            "Open one of your tasks and explore what you can do inside it",
            "Try to mark a task as complete",
        ],
    },
    {
        "name": "Marcus Reid",
        "age": 47,
        "role": "Electrician who runs his own small business",
        "personality": (
            "Not particularly tech-savvy. Uses his phone mainly for calls and texts. "
            "Has tried apps before but finds them complicated. "
            "Values simplicity above everything. Will give up if something takes too long to figure out."
        ),
        "tasks": [
            "Without any instructions, try to figure out how to add a task",
            "Try to add a second task",
            "Try to find any tasks you've completed before",
            "Try to remove a task you no longer need",
        ],
    },
    {
        "name": "Priya Nair",
        "age": 31,
        "role": "Freelance UX designer and mother of two",
        "personality": (
            "Multitasker. Loves voice input because her hands are always full. "
            "Has strong opinions about design — will notice every rough edge. "
            "Uses tasks for both family logistics and client work. Cares about speed and aesthetics."
        ),
        "tasks": [
            "Use voice to add a family task — something like 'pick up kids from school at 3pm Thursday'",
            "Add a work task with some details — like 'send invoice to client, include the PDF'",
            "Tap into one of your tasks and see what the detail view looks like",
            "Check off a subtask if there are any, or try completing a whole task",
            "See if there's a way to filter or organise tasks by type",
        ],
    },
    {
        "name": "Jordan Park",
        "age": 21,
        "role": "University student",
        "personality": (
            "Digital native. High expectations, low patience. "
            "Will try gestures instinctively before reading anything. "
            "Cares about speed and how the app looks. Will absolutely judge the design."
        ),
        "tasks": [
            "Add a task using voice — anything from your life right now",
            "Try swiping on a task to see what happens",
            "Create two more tasks quickly",
            "Tap into a task and explore the detail view",
            "Try to delete a task",
        ],
    },
]

# ── Persona system prompt ─────────────────────────────────────────────────────

APP_CONTEXT = """The app is called Spoke — a voice-first task manager for iPhone, running in the Xcode Simulator.
Key things to know about Spoke:
- The coral (red-orange) microphone button at the bottom is how you create tasks — tap once to start, tap again to stop, or hold and release
- Tasks appear in a scrollable list
- Swipe LEFT on a task row → marks it Done; swipe RIGHT → Deletes it
- Tap a task row to open its detail view
- Filter pills appear under the "spoke •" logo when tasks have tags
- The Simulator window shows an iPhone screen — click within the phone screen area only"""


def persona_system(p: dict) -> str:
    return f"""You are simulating a real user testing an iPhone app for the first time.

YOUR PERSONA:
Name: {p['name']}, age {p['age']}
Role: {p['role']}
Personality: {p['personality']}

{APP_CONTEXT}

HOW TO BEHAVE:
- Act as this person genuinely would — if they'd be confused, show it; if they'd be delighted, say so
- Try each task naturally, the way this person would attempt it
- Note what's easy, what's confusing, what's missing, what's surprising
- After completing all tasks (or giving up on ones that stump you), write a feedback report

IMPORTANT — VOICE INPUT:
When you tap the mic button, voice audio is automatically injected for you by the test harness.
You do NOT need to worry about what to say — just tap the mic button once to start, then wait
a few seconds and tap it again to stop. The system will speak for you in between.

FEEDBACK REPORT FORMAT (write this at the very end, after all tasks):
---FEEDBACK---
Overall rating: X/10
First impression: [one sentence]

What worked well:
- [bullet points]

What was confusing or frustrating:
- [bullet points]

Missing features or things I expected:
- [bullet points]

Design impressions:
[2–3 sentences]

Would I use this app? [Yes / Maybe / No] — [one sentence why]
---END FEEDBACK---"""


def persona_goal(p: dict) -> str:
    tasks = "\n".join(f"{i+1}. {t}" for i, t in enumerate(p["tasks"]))
    return (
        f"You are {p['name']}. Please work through these tasks in order:\n\n{tasks}\n\n"
        "After finishing (or attempting) all tasks, write your feedback report as instructed."
    )


# ── Voice injection ───────────────────────────────────────────────────────────

def generate_voice_phrases(p: dict) -> list[str]:
    """
    Ask Claude Haiku to generate realistic voice phrases this persona would
    naturally say when creating tasks.  Returns 4–6 concrete phrases.
    """
    client = anthropic.Anthropic()
    task_hints = "\n".join(f"- {t}" for t in p["tasks"])
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=300,
        messages=[{
            "role": "user",
            "content": (
                f"You are {p['name']}, {p['age']}, {p['role']}.\n"
                f"Personality: {p['personality']}\n\n"
                f"Generate 5 realistic voice commands you'd speak aloud to a task manager app.\n"
                f"Base them on these intentions:\n{task_hints}\n\n"
                "Rules:\n"
                "- Natural spoken English, not robotic\n"
                "- Include specific details (deadlines, context, names)\n"
                "- Mix work and personal tasks naturally\n"
                "- One phrase per line, no bullets or numbers\n"
                "- 5–12 words each"
            ),
        }],
    )
    phrases = [
        line.strip().strip("-•").strip()
        for line in response.content[0].text.strip().splitlines()
        if line.strip()
    ]
    print(f"\n🗣️  Voice phrases for {p['name']}:")
    for i, ph in enumerate(phrases, 1):
        print(f"   {i}. {ph}")
    return phrases


def make_mic_handler(phrases: list[str]) -> callable:
    """
    Returns a callback for agent.run(on_mic_tap=...).

    Uses a long-press gesture (mousedown → speak → mouseup) so the app treats
    it as a hold-and-release, bypassing tap-mode entirely.

    A 4-second cooldown after each successful recording prevents the agent's
    follow-up clicks from accidentally triggering another cycle.
    """
    queue = list(phrases)
    last_fired = [0.0]  # mutable container so the closure can mutate it
    COOLDOWN = 4.0

    def handler(x: int, y: int):
        now = time.time()
        if now - last_fired[0] < COOLDOWN:
            remaining = COOLDOWN - (now - last_fired[0])
            print(f"  🔇  Mic tap ignored (cooldown {remaining:.1f}s remaining)")
            return

        if not queue:
            print("  🗣️  (no more phrases — ignoring mic tap)")
            return

        phrase = queue.pop(0)
        print(f"  🗣️  Speaking: \"{phrase}\"")

        # Long-press: mousedown starts recording; mouseup after speech stops it.
        # elapsed > 0.3 s → the app treats this as a hold gesture → direct stop,
        # no tap-mode confusion.
        subprocess.run(["cliclick", f"dd:{x},{y}"], capture_output=True)
        time.sleep(0.8)  # wait for recording to start

        subprocess.run(["say", "--rate", "150", phrase])
        time.sleep(0.8)  # brief pause after speech ends

        subprocess.run(["cliclick", f"du:{x},{y}"], capture_output=True)
        print("  ✅  Recording stopped (hold gesture)")

        last_fired[0] = time.time()
        time.sleep(2.5)  # let the app process the transcript before control returns

    return handler


# ── Run a single persona ──────────────────────────────────────────────────────

def run_persona(p: dict, results_dir: Path) -> dict:
    print(f"\n{'═' * 60}")
    print(f"  Persona: {p['name']} — {p['role']}")
    print(f"{'═' * 60}")

    phrases      = generate_voice_phrases(p)
    mic_handler  = make_mic_handler(phrases)

    transcript = agent.run(
        goal=persona_goal(p),
        system=persona_system(p),
        max_steps=40,
        on_mic_tap=mic_handler,
    )

    full_text = "\n".join(transcript)

    # Extract the feedback block
    feedback = ""
    if "---FEEDBACK---" in full_text:
        start = full_text.index("---FEEDBACK---")
        end   = full_text.index("---END FEEDBACK---") + len("---END FEEDBACK---") if "---END FEEDBACK---" in full_text else len(full_text)
        feedback = full_text[start:end].strip()

    result = {
        "persona": p["name"],
        "role": p["role"],
        "transcript": full_text,
        "feedback": feedback or full_text[-3000:],  # fallback: last 3k chars
        "timestamp": datetime.now().isoformat(),
    }

    # Save individual result
    slug = p["name"].lower().replace(" ", "_")
    out_path = results_dir / f"{slug}.json"
    out_path.write_text(json.dumps(result, indent=2))
    print(f"\n💾  Saved → {out_path}")

    return result


# ── PM synthesis ──────────────────────────────────────────────────────────────

PM_SYSTEM = """You are a senior product manager synthesising user research from simulated testing sessions.
Be specific, evidence-based, and actionable. Reference the personas by name when attributing feedback.
Prioritise issues by frequency (mentioned by multiple users) and severity (blocks core usage vs. minor annoyance)."""

PM_PROMPT = """Below are feedback reports from {n} simulated users who tested the Spoke app.

{feedback_blocks}

Please write a product research synthesis report covering:

## Executive Summary
2–3 sentences on overall reception and the single most important finding.

## What's Working
The things users responded positively to, with evidence from the sessions.

## Critical Issues (P0/P1)
Problems that blocked users or caused significant frustration. These need fixing first.

## Friction Points (P2)
Minor but noticeable issues that degraded the experience.

## Missing Features / Unmet Expectations
Things users expected to find but couldn't, or features they asked for.

## Design & Perception
How users reacted to the visual design and overall feel.

## Recommendations (Prioritised)
Numbered list of specific, actionable changes, most important first.

## Persona Breakdown
One short paragraph per persona on their individual experience and suitability as a target user."""


def synthesise(results: list[dict], results_dir: Path) -> str:
    print(f"\n\n{'═' * 60}")
    print("  PM Agent: synthesising feedback...")
    print(f"{'═' * 60}\n")

    feedback_blocks = "\n\n---\n\n".join(
        f"**{r['persona']} ({r['role']})**\n\n{r['feedback']}"
        for r in results
    )

    client = anthropic.Anthropic()
    response = client.messages.create(
        model="claude-opus-4-6",
        max_tokens=4096,
        system=PM_SYSTEM,
        messages=[{
            "role": "user",
            "content": PM_PROMPT.format(n=len(results), feedback_blocks=feedback_blocks),
        }],
    )

    report = response.content[0].text
    print(report)

    # Save report
    ts    = datetime.now().strftime("%Y-%m-%d_%H-%M")
    rpath = results_dir / f"report_{ts}.md"
    rpath.write_text(report)
    print(f"\n\n💾  Report saved → {rpath}")

    return report


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    results_dir = Path(__file__).parent / "results"
    results_dir.mkdir(exist_ok=True)

    args = sys.argv[1:]

    # --pm-only: re-synthesise from saved JSON files
    if "--pm-only" in args:
        results = [json.loads(p.read_text()) for p in sorted(results_dir.glob("*.json"))]
        if not results:
            print("No saved results found in testing/results/")
            sys.exit(1)
        synthesise(results, results_dir)
        return

    # --persona N: run a single persona
    if "--persona" in args:
        idx = int(args[args.index("--persona") + 1])
        result = run_persona(PERSONAS[idx], results_dir)
        synthesise([result], results_dir)
        return

    # Default: run all personas then synthesise
    results = []
    for persona in PERSONAS:
        result = run_persona(persona, results_dir)
        results.append(result)
        # Brief pause between personas so the Simulator settles
        print("\n⏳  Pausing 5s before next persona...")
        time.sleep(5)

    synthesise(results, results_dir)


if __name__ == "__main__":
    main()
