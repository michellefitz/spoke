#!/usr/bin/env python3
"""Run 30 eval transcripts through the Spoke task parser prompt and generate a CSV."""

import json
import csv
import time
import urllib.request
import urllib.error
import os

import sys

# Claude Code strips ANTHROPIC_API_KEY from the shells it spawns, so under a
# Claude Code session the key has to arrive under a different name. Check the
# unreserved name first, then fall back to the standard one for plain shells.
KEY_VARS = ("SPOKE_EVAL_API_KEY", "ANTHROPIC_API_KEY")
API_KEY = next((os.environ[v] for v in KEY_VARS if os.environ.get(v)), None)

if not API_KEY:
    sys.exit(
        "No API key found. Set one of: " + ", ".join(KEY_VARS) + "\n"
        "Under Claude Code, use SPOKE_EVAL_API_KEY — ANTHROPIC_API_KEY is\n"
        "reserved for the session's own auth and is not passed to subprocesses."
    )

OUTDIR = os.path.dirname(os.path.abspath(__file__))

SYSTEM_PROMPT = (
    'Today\'s date is 2026-04-01. You are a task parser. Given a voice transcript, extract one or more tasks. '
    'Rules: '
    '- If the transcript contains MULTIPLE UNRELATED tasks (e.g. "call the dentist, do grocery shopping, and pick up Alex"), return a JSON ARRAY of task objects. '
    '- If the transcript describes a SINGLE task with details or sub-items (e.g. "do the grocery shopping — milk, eggs, and broccoli"), return a JSON ARRAY with ONE object, using bullets in the description for the sub-items. '
    '- Each task object has: "title" (required), "description" (optional), "deadline" (optional), "tag" (optional). '
    '- Title must be action-oriented and at most 50 characters. Keep specific details — times, names, locations — in the title when they fit. "Pick up Alex at 3 PM" is a better title than "Pick up Alex" with "3 PM" in the description. '
    '- Description is for sub-tasks, multi-step context, or detail that genuinely would not fit a 50-character title. Do NOT move times or locations to the description just to shorten the title — only do so if the title truly exceeds 50 characters with them included. '
    '- NEVER silently drop information. If a detail cannot fit the title, it must appear in the description. '
    '- If the description contains 2 or more distinct actions, topics, or steps, you MUST use bullet format — never write multiple ideas as prose sentences. '
    '- When using bullets, always write a short intro sentence first (e.g. "Things to pick up:"), then each bullet on its OWN LINE using \\n as the separator. Each bullet MUST start at the beginning of its line as "• item" — never inline. JSON example: "description": "Things to pick up:\\n• Milk\\n• Eggs\\n• Broccoli" '
    '- Use plain prose only (no bullets) when there is a single sentence of overflow detail. '
    '- Omit description entirely when the title captures everything. '
    '- If the user mentions a date or deadline (e.g. "by next Wednesday", "on Tuesday", "before April 20", "this Friday"), resolve it relative to today and include it as "deadline" in YYYY-MM-DD format. Omit "deadline" if no date is mentioned. A deadline applies only to the task it was mentioned with — do not copy it to other tasks. '
    '- If the task clearly belongs to one of these categories, include it as "tag": personal, work, shopping, health, finance. Omit "tag" if unsure. '
    'Return ONLY a valid JSON ARRAY, no markdown, no code fences, no commentary. '
    'Examples: '
    'Single task: [{"title": "Call the dentist"}] '
    'Single task with details: [{"title": "Do grocery shopping", "description": "Things to pick up:\\n• Milk\\n• Eggs\\n• Broccoli"}] '
    'Multiple tasks: [{"title": "Call the dentist"}, {"title": "Do grocery shopping", "description": "Things to pick up:\\n• Milk\\n• Eggs"}, {"title": "Pick up Alex at 5 PM tomorrow", "deadline": "YYYY-MM-DD"}]'
)

# 30 test cases: (category, transcript, expected_task_count)
TESTS = [
    # Category 1: Simple single tasks (1-5)
    ("simple-single", "Call the dentist", 1),
    ("simple-single", "Take out the trash", 1),
    ("simple-single", "Email Sarah about the project update", 1),
    ("simple-single", "Pay the electric bill", 1),
    ("simple-single", "Pick up my prescription at CVS", 1),

    # Category 2: Single tasks with subtasks (6-10)
    ("single-with-subtasks", "Do the grocery shopping I need milk, eggs, bread, and some chicken thighs", 1),
    ("single-with-subtasks", "Pack for the camping trip this weekend I need the tent, sleeping bags, cooler, flashlight, and bug spray", 1),
    ("single-with-subtasks", "Prep for the Monday morning standup I need to cover the API migration status, the new hire onboarding, and the Q2 roadmap changes", 1),
    ("single-with-subtasks", "Clean the apartment before Mom visits vacuum the living room, clean the bathroom, do the dishes, and change the sheets", 1),
    ("single-with-subtasks", "Get the car ready for the road trip check the oil, fill up the tires, get a car wash, and pack the emergency kit", 1),

    # Category 3: Two-task combinations (11-15)
    ("two-tasks", "I need to call the dentist and also pick up my dry cleaning on the way home", 2),
    ("two-tasks", "Schedule a meeting with the design team for Thursday and submit the expense report by Friday", 2),
    ("two-tasks", "Return the Amazon package and then stop at the bank to deposit that check", 2),
    ("two-tasks", "Book a vet appointment for Luna and renew my gym membership before it expires next week", 2),
    ("two-tasks", "Text Mom happy birthday and order flowers for delivery to her house", 2),

    # Category 4: Rambling/meandering speech (16-20)
    ("rambling", "Oh yeah I just remembered I should probably um call the insurance company because they sent me that letter about the um the policy renewal and I think it said something about like the rate going up so I need to ask them about that before um I think it was before April fifteenth", 1),
    ("rambling", "So I was talking to Jake at lunch and he mentioned that oh wait actually I think it was at coffee anyway he said the presentation deck needs to be updated because the numbers from Q1 are wrong and I was like oh man I totally forgot about that so yeah I need to fix the Q1 numbers in the presentation", 1),
    ("rambling", "Hmm let me think what was it oh right so my landlord texted me and said they're going to do like an inspection or something on um I think he said next Wednesday so I should probably tidy up a bit and also I think there's that thing where the kitchen faucet is leaking I should mention that to him when he comes", 2),
    ("rambling", "OK so like I've been meaning to do this for ages but I really need to cancel that streaming service I never use anymore I think it's like Paramount Plus or something and it's been charging me like fifteen dollars a month and I keep forgetting", 1),
    ("rambling", "Wait what was I going to say oh yeah so Sarah mentioned that the um the book club meeting got moved to next Tuesday and I still haven't finished reading the book so I really need to finish that before Tuesday I think I have like three chapters left", 1),

    # Category 5: Complex brain dumps (21-25)
    ("complex-braindump", "OK so I have a bunch of stuff this week first I need to schedule a dentist appointment and then I have to buy groceries we need pasta sauce chicken rice and broccoli oh and I also need to submit my timesheet by Friday and call the landlord about the broken heater", 4),
    ("complex-braindump", "Alright Monday things I need to send the proposal to the client by end of day Tuesday I have that doctor appointment at 2 PM don't forget to fast beforehand and I need to pick up a birthday gift for Dad his birthday is Saturday and also transfer money to savings this week at least five hundred dollars", 4),
    ("complex-braindump", "Let me brain dump OK so for work I need to review the pull requests and write the technical spec for the new feature those are both due by Wednesday then personal stuff I need to book flights for the vacation in June and renew my passport before that oh and schedule the dog grooming appointment sometime this week", 5),
    ("complex-braindump", "Things I cannot forget this week file taxes by April fifteenth buy a new laptop charger the old one is fraying return the library books they are way overdue send a thank you note to Grandma for the birthday money and make a dentist appointment for a cleaning", 5),
    ("complex-braindump", "So many things OK number one meal prep for the week I want to make chili and some overnight oats number two research new health insurance plans the enrollment deadline is April tenth number three sign up for that pottery class at the community center and number four fix the squeaky door in the bedroom", 4),

    # Category 6: Stress tests (26-30)
    ("stress-test", "Ugh I don't know there's just like so much stuff um I think I need to maybe look into that thing with the um the car registration it's expired or it's about to expire I don't remember which", 1),
    ("stress-test", "Hey so like you know that thing where um oh man what's it called the the thing for work where they want us to do the training module the compliance one yeah I should probably do that soon they keep sending me emails about it", 1),
    ("stress-test", "Oh shoot I just realized um OK so there's the thing with the the package that was supposed to come and I think it went to the wrong address so I need to like contact them or whatever and also my mom called and she wants me to um what did she say oh yeah help her set up her new phone this weekend", 2),
    ("stress-test", "Blah blah blah OK fine I'll do it um so basically I need to like figure out dinner for tonight I don't know maybe order something or go to the store whatever and then um I think there was a bill that was due like soon the water bill or maybe electric I should check and oh also I keep forgetting to text Mike back about the camping trip thing", 3),
    ("stress-test", "I'm like so scattered today um what do I OK so I think maybe I should probably start working on that essay that's due I think next Monday for the writing class and uh also I had this idea to rearrange the living room furniture but I don't know if that counts as a task ha ha and my sister wanted me to help with the party planning so", 3),
]


def call_api(transcript):
    """Call the Claude API with a transcript and return the parsed JSON response."""
    body = json.dumps({
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 800,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": f'Transcript: "{transcript}"'}]
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=body,
        headers={
            "x-api-key": API_KEY,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            text = data["content"][0]["text"]
            return text
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8")
        print(f"  HTTP Error {e.code}: {error_body}")
        return "[]"
    except Exception as e:
        print(f"  Error: {e}")
        return "[]"


def parse_response(text):
    """Parse the JSON response text into a list of task dicts."""
    # Strip markdown fences if present
    stripped = text.strip()
    if stripped.startswith("```"):
        lines = stripped.split("\n")
        stripped = "\n".join(lines[1:-1]).strip()

    try:
        result = json.loads(stripped)
        if isinstance(result, list):
            return result
        elif isinstance(result, dict):
            return [result]
    except json.JSONDecodeError:
        print(f"  JSON parse failed: {text[:100]}")
    return []


def main():
    results = []

    print("Running 30 eval tests...\n")

    for i, (category, transcript, expected) in enumerate(TESTS, 1):
        print(f"Test {i}/30 [{category}]: {transcript[:60]}...")

        raw_response = call_api(transcript)
        tasks = parse_response(raw_response)
        actual_count = len(tasks)

        print(f"  Expected: {expected}, Got: {actual_count}")
        for j, t in enumerate(tasks):
            print(f"    Task {j+1}: {t.get('title', '???')}")

        results.append({
            "test_num": i,
            "category": category,
            "transcript": transcript,
            "expected": expected,
            "actual": actual_count,
            "tasks": tasks,
            "raw": raw_response,
        })

        # Rate limit pause
        if i < 30:
            time.sleep(0.8)

    # Write CSV
    csv_path = os.path.join(OUTDIR, "eval-run-1.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "Test #", "Category", "Transcript", "Expected Tasks", "Actual Tasks",
            "Task 1 Title", "Task 1 Description", "Task 1 Deadline", "Task 1 Tag",
            "Task 2 Title", "Task 2 Description", "Task 2 Deadline", "Task 2 Tag",
            "Task 3 Title", "Task 3 Description", "Task 3 Deadline", "Task 3 Tag",
            "Task 4 Title", "Task 4 Description", "Task 4 Deadline", "Task 4 Tag",
            "Task 5 Title", "Task 5 Description", "Task 5 Deadline", "Task 5 Tag",
            "Pass/Fail", "Notes",
        ])

        for r in results:
            row = [
                r["test_num"],
                r["category"],
                r["transcript"],
                r["expected"],
                r["actual"],
            ]
            # Up to 5 tasks
            for j in range(5):
                if j < len(r["tasks"]):
                    t = r["tasks"][j]
                    row.extend([
                        t.get("title", ""),
                        t.get("description", ""),
                        t.get("deadline", ""),
                        t.get("tag", ""),
                    ])
                else:
                    row.extend(["", "", "", ""])
            row.extend(["", ""])  # Pass/Fail, Notes (blank for manual scoring)
            writer.writerow(row)

    print(f"\nCSV written to: {csv_path}")

    # Write raw JSON for reference
    raw_path = os.path.join(OUTDIR, "eval-run-1-raw.json")
    with open(raw_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print(f"Raw JSON written to: {raw_path}")

    # Print summary stats
    print(f"\n--- Summary ---")
    correct_count = sum(1 for r in results if r["expected"] == r["actual"])
    print(f"Task count match: {correct_count}/30 ({correct_count/30*100:.0f}%)")

    for cat in ["simple-single", "single-with-subtasks", "two-tasks", "rambling", "complex-braindump", "stress-test"]:
        cat_results = [r for r in results if r["category"] == cat]
        cat_correct = sum(1 for r in cat_results if r["expected"] == r["actual"])
        print(f"  {cat}: {cat_correct}/{len(cat_results)}")


if __name__ == "__main__":
    main()
