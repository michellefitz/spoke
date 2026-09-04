"""Eval scenarios for Spoke's assistant parse.

Everything is pinned to Wednesday 12 August 2026 so date expectations are
exact. That week:

    today     Wed 2026-08-12      Sun  2026-08-16
    tomorrow  Thu 2026-08-13      Mon  2026-08-17
    Fri       2026-08-14          Tue  2026-08-18
    Sat       2026-08-15          Wed  2026-08-19
                                  Thu  2026-08-20

Assertions available (all optional; omit what a case doesn't care about):

    n_actions      exact number of actions
    kinds          expected action kinds, order-insensitive:
                   "create" | "edit" | "event" | "edit-event"
    titles_include substrings that must each appear in some action's title
    deadline_of    {title substring: "2026-08-14" | "this-week" | None}
    no_deadline    [title substrings] that must carry no deadline
    tag_of         {title substring: "shopping"}
    event_of       {title substring: {"date":…, "start":…, "end":…}}
    matches        expected "match" values on edit / edit-event actions
    focus          what's on screen: {"kind": "event"|"task", "title": ...,
                   "start"/"end" for events, "description" for tasks}
    asks_question  True / False
    bullets_in     title substring whose description must be a bullet list
    preserves      strings that must survive somewhere in title+description
    max_title      overridden title length cap (default 50)

`why` is the point of the case — read it when a failure looks pedantic.
"""

TODAY = "2026-08-12"

# Reusable fixtures ──────────────────────────────────────────────────────────

TASKS_TYPICAL = [
    {"title": "Do grocery shopping", "description": "Things to pick up:\n• Milk\n• Eggs"},
    {"title": "Book dentist appointment"},
    {"title": "Prepare list of jobs for cleaner"},
    {"title": "Sort out the loft"},
]

EVENTS_TYPICAL = [
    {"title": "Hair appointment", "start": "2026-08-14T10:00", "end": "2026-08-14T11:00"},
    {"title": "Alex karate", "start": "2026-08-14T16:30", "end": "2026-08-14T17:30"},
    {"title": "Dentist", "start": "2026-08-13T11:00", "end": "2026-08-13T12:15"},
]


SCENARIOS = [

    # ── Straightforward capture ──────────────────────────────────────────────
    dict(
        id="simple-01", category="simple",
        why="The most common input of all. One task, no embellishment, no question.",
        transcript="I need to put the bins out tonight",
        expect=dict(n_actions=1, kinds=["create"], titles_include=["bins"], asks_question=False),
    ),
    dict(
        id="simple-02", category="simple",
        why="A verb-less fragment should still become an action-oriented task.",
        transcript="milk and bread from the shop on the way home",
        expect=dict(kinds=["create"], preserves=["milk", "bread"]),
    ),
    dict(
        id="simple-03", category="simple",
        why="Politeness and filler must not become part of the title.",
        transcript="um so I was thinking I should probably ring the plumber about the leak",
        expect=dict(n_actions=1, kinds=["create"], titles_include=["plumber"]),
    ),

    # ── Braindumps: the core promise ─────────────────────────────────────────
    dict(
        id="dump-01", category="braindump",
        why="Three unrelated things in one breath — the thing Spoke exists for.",
        transcript="right I need to book the car in for a service, ring the school about the trip money, and pick up a birthday present for Sam",
        expect=dict(n_actions=3, kinds=["create"] * 3,
                    titles_include=["car", "school", "present"]),
    ),
    dict(
        id="dump-02", category="braindump",
        why="Eight items. Tests that nothing gets dropped when the list is long.",
        transcript="okay brain dump, bins out, book the MOT, ring mum back, order Alex's school shoes, cancel the gym membership, get a birthday card for Órla, chase the plumber, and sort the recycling",
        expect=dict(n_actions=8, preserves=["MOT", "mum", "shoes", "gym", "Órla", "plumber"]),
    ),
    dict(
        id="dump-03", category="braindump",
        why="Related-sounding but genuinely separate errands should not be merged.",
        transcript="I need to go to the post office and also the pharmacy to pick up my prescription",
        expect=dict(n_actions=2, kinds=["create", "create"]),
    ),

    # ── Sub-items become bullets ─────────────────────────────────────────────
    dict(
        id="bullets-01", category="bullets",
        why="One task with a shopping list inside it — one action, bulleted description.",
        transcript="do the big shop, we need milk, eggs, bread, chicken and something for Friday dinner",
        expect=dict(n_actions=1, kinds=["create"], bullets_in="shop",
                    preserves=["milk", "eggs", "bread", "chicken"]),
    ),
    dict(
        id="bullets-02", category="bullets",
        why="Multi-step single job. Steps belong in bullets, not as separate tasks.",
        transcript="get the spare room ready for mum, change the sheets, clear the boxes out, and put a towel in there",
        expect=dict(n_actions=1, bullets_in="spare room",
                    preserves=["sheets", "boxes", "towel"]),
    ),

    # ── Named days ───────────────────────────────────────────────────────────
    dict(
        id="date-01", category="dates",
        why="Named weekday resolves to that day, not the day before or after.",
        transcript="I need to send the form back by Friday",
        expect=dict(n_actions=1, deadline_of={"form": "2026-08-14"}),
    ),
    dict(
        id="date-02", category="dates",
        why="'Next Tuesday' from a Wednesday means the Tuesday six days out.",
        transcript="remind me to renew the parking permit next Tuesday",
        expect=dict(n_actions=1, deadline_of={"parking": "2026-08-18"}),
    ),
    dict(
        id="date-03", category="dates",
        why="'Tomorrow' is the single most common relative date.",
        transcript="I have to drop the forms into the office tomorrow",
        expect=dict(n_actions=1, deadline_of={"forms": "2026-08-13"}),
    ),
    dict(
        id="date-04", category="dates",
        why="A named day already past this week means the one coming up.",
        transcript="get the recycling sorted by Monday",
        expect=dict(n_actions=1, deadline_of={"recycling": "2026-08-17"}),
    ),
    dict(
        id="date-05", category="dates",
        why="Explicit calendar date, spoken aloud.",
        transcript="the insurance renewal is due on the twentieth of August, I need to sort it",
        expect=dict(n_actions=1, deadline_of={"insurance": "2026-08-20"}),
    ),

    # ── Week buckets: the anti-fake-deadline rule ────────────────────────────
    dict(
        id="week-01", category="week-buckets",
        why="'This week' must stay a week bucket. Inventing a day is the exact "
            "behaviour Spoke's positioning is built against.",
        transcript="I need to book the MOT sometime this week",
        expect=dict(n_actions=1, deadline_of={"MOT": "this-week"}),
    ),
    dict(
        id="week-02", category="week-buckets",
        why="Same for next week.",
        transcript="I want to get the loft cleared out next week at some point",
        expect=dict(n_actions=1, deadline_of={"loft": "next-week"}),
    ),
    dict(
        id="week-03", category="week-buckets",
        why="No time reference at all means no deadline — not today by default.",
        transcript="I should really get round to sorting the photo albums",
        expect=dict(n_actions=1, no_deadline=["photo"]),
    ),

    # ── Deadline scope: a date attaches to one task only ─────────────────────
    dict(
        id="scope-01", category="deadline-scope",
        why="Friday belongs to the milk run only. Leaking it onto the dentist "
            "is a silent wrong-date bug the user won't notice until too late.",
        transcript="ring the dentist, and pick up milk on Friday",
        expect=dict(n_actions=2, deadline_of={"milk": "2026-08-14"}, no_deadline=["dentist"]),
    ),
    dict(
        id="scope-02", category="deadline-scope",
        why="Two tasks, two different days — neither should borrow the other's.",
        transcript="bins out Thursday and the recycling goes out Monday",
        expect=dict(n_actions=2,
                    deadline_of={"bins": "2026-08-13", "recycling": "2026-08-17"}),
    ),
    dict(
        id="scope-03", category="deadline-scope",
        why="A leading date shouldn't spread across everything that follows.",
        transcript="on Friday I need to collect the dry cleaning, and at some point I should book a haircut",
        expect=dict(n_actions=2, deadline_of={"dry cleaning": "2026-08-14"},
                    no_deadline=["haircut"]),
    ),

    # ── Events vs tasks ──────────────────────────────────────────────────────
    dict(
        id="event-01", category="events",
        why="Appointment at a clock time on a day — a calendar event.",
        transcript="I've got a dentist appointment next Tuesday at eleven",
        expect=dict(n_actions=1, kinds=["event"],
                    event_of={"dentist": {"date": "2026-08-18", "start": "11:00"}}),
    ),
    dict(
        id="event-02", category="events",
        why="Booking the appointment is a task; having it is an event. This is "
            "the single most confusable pair in the whole product.",
        transcript="I need to book a dentist appointment",
        expect=dict(n_actions=1, kinds=["create"]),
    ),
    dict(
        id="event-03", category="events",
        why="A deadline time is not an appointment.",
        transcript="finish the report by five o'clock tomorrow",
        expect=dict(n_actions=1, kinds=["create"], deadline_of={"report": "2026-08-13"}),
    ),
    dict(
        id="event-04", category="events",
        why="Appointment with no clock time is a task with a deadline, not an event.",
        transcript="I've got to see the dentist sometime next week",
        expect=dict(n_actions=1, kinds=["create"], deadline_of={"dentist": "next-week"}),
    ),
    dict(
        id="event-05", category="events",
        why="Explicit start and end times should both be captured.",
        transcript="lunch with Sarah on Friday from one to two",
        expect=dict(n_actions=1, kinds=["event"],
                    event_of={"Sarah": {"date": "2026-08-14", "start": "13:00", "end": "14:00"}}),
    ),
    dict(
        id="event-06", category="events",
        why="Mixed input: one appointment and one errand in the same breath.",
        transcript="parents evening is on Thursday at half six, and I need to buy a card before then",
        expect=dict(n_actions=2, kinds=["event", "create"],
                    event_of={"parents": {"date": "2026-08-13", "start": "18:30"}}),
    ),

    # ── Edits against existing tasks ─────────────────────────────────────────
    dict(
        id="edit-01", category="edits", tasks=TASKS_TYPICAL,
        why="Adding to a named existing list is the textbook edit.",
        transcript="add bananas and coffee to the grocery shopping",
        expect=dict(n_actions=1, kinds=["edit"], matches=["Do grocery shopping"],
                    preserves=["bananas", "coffee", "Milk", "Eggs"]),
    ),
    dict(
        id="edit-02", category="edits", tasks=TASKS_TYPICAL,
        why="REGRESSION: a deadline-only edit carries no title. Spoke used to "
            "drop the action silently and still say it had done it.",
        transcript="set the deadline on the cleaner list to today",
        expect=dict(n_actions=1, kinds=["edit"],
                    matches=["Prepare list of jobs for cleaner"],
                    deadline_of={"cleaner": "2026-08-12"}),
    ),
    dict(
        id="edit-03", category="edits", tasks=TASKS_TYPICAL,
        why="A vague back-reference should still land on the right task.",
        transcript="actually push the loft thing to next week",
        expect=dict(n_actions=1, kinds=["edit"], matches=["Sort out the loft"],
                    deadline_of={"loft": "next-week"}),
    ),
    dict(
        id="edit-04", category="edits", tasks=TASKS_TYPICAL,
        why="Editing must merge, never overwrite: the existing bullets survive.",
        transcript="on the grocery shopping, we also need washing up liquid",
        expect=dict(kinds=["edit"], preserves=["Milk", "Eggs", "washing up liquid"]),
    ),
    dict(
        id="edit-05", category="edits", tasks=TASKS_TYPICAL,
        why="Something genuinely new is a create even when the list is full.",
        transcript="I need to order a new bin for the garden",
        expect=dict(n_actions=1, kinds=["create"]),
    ),

    # ── Edits against calendar events ────────────────────────────────────────
    dict(
        id="event-edit-01", category="edit-events", tasks=TASKS_TYPICAL, events=EVENTS_TYPICAL,
        why="Moving a real appointment edits the event, not a similar task.",
        transcript="move my hair appointment to two o'clock",
        expect=dict(n_actions=1, kinds=["edit-event"], matches=["Hair appointment"]),
    ),
    dict(
        id="event-edit-02", category="edit-events", tasks=TASKS_TYPICAL, events=EVENTS_TYPICAL,
        why="'Dentist' exists as both a task and an event — the calendar wins "
            "when the user talks about rescheduling.",
        transcript="push tomorrow's dentist back by an hour",
        expect=dict(n_actions=1, kinds=["edit-event"], matches=["Dentist"]),
    ),
    dict(
        id="event-edit-03", category="edit-events", tasks=TASKS_TYPICAL, events=EVENTS_TYPICAL,
        why="Booking is still a task even with a same-named event on the calendar.",
        transcript="I need to book Alex's next karate term",
        expect=dict(n_actions=1, kinds=["create"]),
    ),

    # ── Clarifying questions: ask when it matters, not otherwise ─────────────
    dict(
        id="clarify-01", category="clarify", tasks=TASKS_TYPICAL,
        why="A near-duplicate of an existing task is the one case worth asking about.",
        transcript="I need to ring the dentist and get an appointment booked in",
        expect=dict(asks_question=True, n_actions=0),
    ),
    dict(
        id="clarify-02", category="clarify", tasks=TASKS_TYPICAL,
        why="Clear input must NOT trigger a question. Over-asking is the more "
            "annoying failure and the harder one to notice in casual testing.",
        transcript="pick up a birthday cake for Saturday",
        expect=dict(asks_question=False, n_actions=1),
    ),
    dict(
        id="clarify-03", category="clarify",
        why="An empty list can't contain duplicates, so nothing to ask about.",
        transcript="book flights for the October half term",
        expect=dict(asks_question=False),
    ),

    # ── Information must survive ─────────────────────────────────────────────
    dict(
        id="info-01", category="info-loss",
        why="Quantities and specifics are exactly what people trust it to keep.",
        transcript="order six party bags and twelve balloons for Saturday, and get a cake from the bakery on the high street",
        expect=dict(preserves=["six", "twelve", "bakery"]),
    ),
    dict(
        id="info-02", category="info-loss",
        why="Too long for a 50-char title, so the detail must land in the description.",
        transcript="ring the surgery and ask whether Alex's asthma review needs to be in person or if they can do it over the phone",
        expect=dict(n_actions=1, preserves=["asthma", "phone"]),
    ),
    dict(
        id="info-03", category="info-loss",
        why="Proper nouns and places must not be normalised away.",
        transcript="confirm the playdate with Chloe at Manooth on Sunday at two",
        expect=dict(preserves=["Chloe", "Manooth"]),
    ),

    # ── Messy real speech ────────────────────────────────────────────────────
    dict(
        id="messy-01", category="messy-speech",
        why="Self-correction: the later value wins, the earlier one is discarded.",
        transcript="pick Alex up at three, no wait, four o'clock on Friday",
        expect=dict(n_actions=1, preserves=["four"]),
    ),
    dict(
        id="messy-02", category="messy-speech",
        why="A false start followed by the real request.",
        transcript="I need to, hang on, no, I need to email the school about the uniform order",
        expect=dict(n_actions=1, titles_include=["school"]),
    ),
    dict(
        id="messy-03", category="messy-speech",
        why="Trailing off mid-sentence should still produce something usable.",
        transcript="and then there's the thing with the car, the insurance, I need to sort that out before",
        expect=dict(n_actions=1, preserves=["insurance"]),
    ),
    dict(
        id="messy-04", category="messy-speech",
        why="Transcription mangles initialisms. Should still be recognisable.",
        transcript="I need to book the car in for its M O T next month",
        expect=dict(n_actions=1),
    ),

    # ── Things that are not tasks ────────────────────────────────────────────
    dict(
        id="nontask-01", category="non-tasks",
        why="Thinking aloud with no request. Junk tasks erode trust fast.",
        transcript="um what was I saying, hang on, no I've lost it",
        expect=dict(n_actions=0),
    ),
    dict(
        id="nontask-02", category="non-tasks",
        why="A question about the list is not a new task.",
        transcript="what have I got on this week",
        expect=dict(n_actions=0),
    ),

    # ── Instructions about the thing on screen ───────────────────────────────
    dict(
        id="focus-01", category="focus", tasks=TASKS_TYPICAL, events=EVENTS_TYPICAL,
        focus={"kind": "event", "title": "Hair appointment",
               "start": "2026-08-14T10:00", "end": "2026-08-14T11:00"},
        why="Looking at an event and saying 'move this' must edit THAT event. "
            "Without screen context the model had to guess from the list.",
        transcript="move this to three in the afternoon",
        expect=dict(n_actions=1, kinds=["edit-event"], matches=["Hair appointment"],
                    asks_question=False),
    ),
    dict(
        id="focus-02", category="focus", tasks=TASKS_TYPICAL, events=EVENTS_TYPICAL,
        focus={"kind": "event", "title": "Playdate with Cloe",
               "start": "2026-08-15T14:00", "end": "2026-08-15T16:00"},
        why="REGRESSION: correcting a misspelled name on the open event did "
            "nothing at all. It must produce an edit-event retitling it.",
        transcript="the name is spelled wrong, it should be Chloe, C H L O E",
        expect=dict(n_actions=1, kinds=["edit-event"],
                    matches=["Playdate with Cloe"], preserves=["Chloe"]),
    ),
    dict(
        id="focus-03", category="focus", tasks=TASKS_TYPICAL,
        focus={"kind": "task", "title": "Sort out the loft", "description": None},
        why="Same for a task: 'push this to Friday' edits the open one.",
        transcript="push this one to Friday",
        expect=dict(n_actions=1, kinds=["edit"], matches=["Sort out the loft"],
                    deadline_of={"loft": "2026-08-14"}),
    ),

    # ── Referring to something Spoke cannot see ──────────────────────────────
    dict(
        id="unfound-01", category="unfound", tasks=TASKS_TYPICAL, events=EVENTS_TYPICAL,
        why="REGRESSION: the event wasn't in the list, so Spoke invented an "
            "edit-event, said it had moved it, and silently dropped the action. "
            "It must ask instead of guessing.",
        transcript="move the parents evening on the seventh of September to the sixth",
        expect=dict(n_actions=0, asks_question=True),
    ),
    dict(
        id="unfound-02", category="unfound", tasks=TASKS_TYPICAL, events=EVENTS_TYPICAL,
        why="An edit naming a task that doesn't exist shouldn't quietly become "
            "a brand new task with a half-understood title either.",
        transcript="change the deadline on the passport renewal to next week",
        expect=dict(asks_question=True),
    ),

    # ── Tags ─────────────────────────────────────────────────────────────────
    dict(
        id="tag-01", category="tags",
        why="An obvious shopping errand should be tagged.",
        transcript="pick up washing powder and kitchen roll from the supermarket",
        expect=dict(tag_of={"": "shopping"}),
    ),
    dict(
        id="tag-02", category="tags",
        why="Only the configured tags may be used — no invented categories.",
        transcript="book the dog in for his booster jab at the vet",
        expect=dict(n_actions=1),
    ),
]


def by_category():
    groups = {}
    for case in SCENARIOS:
        groups.setdefault(case["category"], []).append(case)
    return groups
