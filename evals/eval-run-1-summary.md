# Eval Run 1 - Task Parser Evaluation Summary

**Date:** 2026-03-30
**Model:** claude-haiku-4-5-20251001
**System prompt date:** 2026-04-01
**Tags available:** personal, work, shopping, health, finance

## Overall Results

- **Task count accuracy:** 29/30 (97%)
- **Only miss:** Test 20 (rambling category) - returned 2 tasks instead of expected 1

### By Category

| Category | Count Match | Notes |
|---|---|---|
| Simple single tasks | 5/5 | Perfect |
| Single tasks with subtasks | 5/5 | Perfect - all used bullet format correctly |
| Two-task combinations | 5/5 | Perfect |
| Rambling/meandering speech | 4/5 | Test 20 split into 2 tasks (debatable) |
| Complex brain dumps | 5/5 | Perfect |
| Stress tests | 5/5 | Perfect |

---

## Test Transcripts by Category

### Category 1: Simple Single Tasks (Tests 1-5)

**Test 1:** "Call the dentist"
- Result: Call the dentist (no tag)

**Test 2:** "Take out the trash"
- Result: Take out the trash (tag: personal)

**Test 3:** "Email Sarah about the project update"
- Result: Email Sarah about the project update (tag: work)

**Test 4:** "Pay the electric bill"
- Result: Pay the electric bill (tag: finance)

**Test 5:** "Pick up my prescription at CVS"
- Result: Pick up prescription at CVS (tag: health)

---

### Category 2: Single Tasks with Subtasks (Tests 6-10)

**Test 6:** "Do the grocery shopping I need milk, eggs, bread, and some chicken thighs"
- Result: 1 task - "Do grocery shopping" with bullets for milk, eggs, bread, chicken thighs (tag: shopping)

**Test 7:** "Pack for the camping trip this weekend I need the tent, sleeping bags, cooler, flashlight, and bug spray"
- Result: 1 task - "Pack for camping trip this weekend" with 5 bullet items, deadline 2026-04-05 (tag: personal)

**Test 8:** "Prep for the Monday morning standup I need to cover the API migration status, the new hire onboarding, and the Q2 roadmap changes"
- Result: 1 task - "Prep for Monday morning standup" with 3 bullet items, deadline 2026-04-06 (tag: work)

**Test 9:** "Clean the apartment before Mom visits vacuum the living room, clean the bathroom, do the dishes, and change the sheets"
- Result: 1 task - "Clean the apartment before Mom visits" with 4 bullet items (tag: personal)

**Test 10:** "Get the car ready for the road trip check the oil, fill up the tires, get a car wash, and pack the emergency kit"
- Result: 1 task - "Get the car ready for the road trip" with 4 bullet items (tag: personal)

---

### Category 3: Two-Task Combinations (Tests 11-15)

**Test 11:** "I need to call the dentist and also pick up my dry cleaning on the way home"
- Result: 2 tasks - "Call the dentist" (health) + "Pick up dry cleaning on the way home" (personal)

**Test 12:** "Schedule a meeting with the design team for Thursday and submit the expense report by Friday"
- Result: 2 tasks - "Schedule meeting with design team" (deadline 2026-04-02, work) + "Submit expense report" (deadline 2026-04-03, work)

**Test 13:** "Return the Amazon package and then stop at the bank to deposit that check"
- Result: 2 tasks - "Return the Amazon package" + "Deposit check at the bank" (no tags)

**Test 14:** "Book a vet appointment for Luna and renew my gym membership before it expires next week"
- Result: 2 tasks - "Book vet appointment for Luna" (personal) + "Renew gym membership" (deadline 2026-04-07, personal)

**Test 15:** "Text Mom happy birthday and order flowers for delivery to her house"
- Result: 2 tasks - "Text Mom happy birthday" (no tag) + "Order flowers for delivery to Mom's house" (personal)

---

### Category 4: Rambling/Meandering Speech (Tests 16-20)

**Test 16:** "Oh yeah I just remembered I should probably um call the insurance company because they sent me that letter about the um the policy renewal and I think it said something about like the rate going up so I need to ask them about that before um I think it was before April fifteenth"
- Result: 1 task - "Call insurance company about policy renewal" with description about rate increase, deadline 2026-04-15 (finance)

**Test 17:** "So I was talking to Jake at lunch and he mentioned that oh wait actually I think it was at coffee anyway he said the presentation deck needs to be updated because the numbers from Q1 are wrong and I was like oh man I totally forgot about that so yeah I need to fix the Q1 numbers in the presentation"
- Result: 1 task - "Fix Q1 numbers in presentation deck" (work)

**Test 18:** "Hmm let me think what was it oh right so my landlord texted me and said they're going to do like an inspection or something on um I think he said next Wednesday so I should probably tidy up a bit and also I think there's that thing where the kitchen faucet is leaking I should mention that to him when he comes"
- Result: 2 tasks - "Tidy up for landlord inspection" (deadline 2026-04-08) + "Tell landlord about leaking kitchen faucet" (deadline 2026-04-08)

**Test 19:** "OK so like I've been meaning to do this for ages but I really need to cancel that streaming service I never use anymore I think it's like Paramount Plus or something and it's been charging me like fifteen dollars a month and I keep forgetting"
- Result: 1 task - "Cancel Paramount Plus subscription" (finance)

**Test 20 (MISMATCH):** "Wait what was I going to say oh yeah so Sarah mentioned that the um the book club meeting got moved to next Tuesday and I still haven't finished reading the book so I really need to finish that before Tuesday I think I have like three chapters left"
- Expected: 1 task (finish the book)
- Got: 2 tasks - "Finish reading book for club" (deadline 2026-04-07) + "Attend book club meeting" (deadline 2026-04-07)
- Note: The model inferred an implicit "attend" task. Debatable whether this is correct -- the user's actionable intent was really just to finish reading. The meeting attendance is context, not a task they asked for.

---

### Category 5: Complex Brain Dumps (Tests 21-25)

**Test 21:** "OK so I have a bunch of stuff this week first I need to schedule a dentist appointment and then I have to buy groceries we need pasta sauce chicken rice and broccoli oh and I also need to submit my timesheet by Friday and call the landlord about the broken heater"
- Result: 4 tasks - dentist (health), groceries with 4 bullets (shopping), timesheet by Friday (work), landlord (personal)

**Test 22:** "Alright Monday things I need to send the proposal to the client by end of day Tuesday I have that doctor appointment at 2 PM don't forget to fast beforehand and I need to pick up a birthday gift for Dad his birthday is Saturday and also transfer money to savings this week at least five hundred dollars"
- Result: 4 tasks - proposal by Tue (work), doctor appt with fasting note (health), birthday gift by Sat (personal), transfer $500 (finance)
- Note: "Dad's birthday is Saturday" was set as deadline 2026-04-04 which is a Saturday. The gift deadline should arguably be before Saturday, not on it. Worth evaluating.

**Test 23:** "Let me brain dump OK so for work I need to review the pull requests and write the technical spec for the new feature those are both due by Wednesday then personal stuff I need to book flights for the vacation in June and renew my passport before that oh and schedule the dog grooming appointment sometime this week"
- Result: 5 tasks - PRs by Wed (work), spec by Wed (work), flights (personal), passport (personal), dog grooming this week (personal)
- Note: "due by Wednesday" resolved to 2026-04-01 which is the same as "today" in the prompt. Should arguably be 2026-04-01 (today is Wednesday April 1, 2026). Correct!

**Test 24:** "Things I cannot forget this week file taxes by April fifteenth buy a new laptop charger the old one is fraying return the library books they are way overdue send a thank you note to Grandma for the birthday money and make a dentist appointment for a cleaning"
- Result: 5 tasks - taxes by Apr 15 (finance), charger with fraying note (shopping), library books with overdue note (personal), thank you note (personal), dentist (health)

**Test 25:** "So many things OK number one meal prep for the week I want to make chili and some overnight oats number two research new health insurance plans the enrollment deadline is April tenth number three sign up for that pottery class at the community center and number four fix the squeaky door in the bedroom"
- Result: 4 tasks - meal prep with bullets (personal), insurance by Apr 10 (health), pottery class (personal), squeaky door (personal)

---

### Category 6: Stress Tests (Tests 26-30)

**Test 26:** "Ugh I don't know there's just like so much stuff um I think I need to maybe look into that thing with the um the car registration it's expired or it's about to expire I don't remember which"
- Result: 1 task - "Check car registration status" with description about determining expiry (personal)

**Test 27:** "Hey so like you know that thing where um oh man what's it called the the thing for work where they want us to do the training module the compliance one yeah I should probably do that soon they keep sending me emails about it"
- Result: 1 task - "Complete compliance training module" (work)

**Test 28:** "Oh shoot I just realized um OK so there's the thing with the the package that was supposed to come and I think it went to the wrong address so I need to like contact them or whatever and also my mom called and she wants me to um what did she say oh yeah help her set up her new phone this weekend"
- Result: 2 tasks - "Contact package delivery about wrong address" (personal) + "Help mom set up her new phone this weekend" (deadline 2026-04-05, personal)

**Test 29:** "Blah blah blah OK fine I'll do it um so basically I need to like figure out dinner for tonight I don't know maybe order something or go to the store whatever and then um I think there was a bill that was due like soon the water bill or maybe electric I should check and oh also I keep forgetting to text Mike back about the camping trip thing"
- Result: 3 tasks - dinner with description (personal), check bill (finance), text Mike (personal)

**Test 30:** "I'm like so scattered today um what do I OK so I think maybe I should probably start working on that essay that's due I think next Monday for the writing class and uh also I had this idea to rearrange the living room furniture but I don't know if that counts as a task ha ha and my sister wanted me to help with the party planning so"
- Result: 3 tasks - essay by Monday (work), rearrange furniture (personal), help sister (personal)
- Note: The model tagged the essay as "work" -- could be debated since it's for a "writing class" which could be personal/education. Also, the user explicitly said "I don't know if that counts as a task" about the furniture, but the model included it anyway. Reasonable choice.

---

## Key Observations

1. **Task count accuracy is excellent** (97%). The parser reliably identifies the correct number of distinct tasks.

2. **Filler word handling is strong.** Even heavily rambling transcripts with "um", "like", "oh wait", etc. were parsed cleanly.

3. **Subtask bullet formatting works consistently.** All single-task-with-subtasks tests produced proper bullet format.

4. **Tag assignment is reasonable** but sometimes inconsistent (Test 1 "Call the dentist" got no tag, but Test 11 "Call the dentist" got health tag). Worth investigating consistency.

5. **Deadline resolution looks correct** for clear date references. "This weekend" -> Apr 5 (Sunday), "next Wednesday" -> Apr 8, "by Friday" -> Apr 3 (Friday).

6. **One debatable failure:** Test 20 created an "Attend book club meeting" task that wasn't explicitly requested. The model inferred it from context. This is the kind of over-extraction that could annoy users.

7. **Edge case in Test 30:** Model included the furniture rearranging despite the user hedging ("I don't know if that counts"). This is arguably the right call -- better to capture it and let the user delete than miss it.

## Areas for Manual Evaluation

- Title quality (are titles action-oriented, concise, specific?)
- Description quality (are bullets well-formatted? Is prose used appropriately?)
- Tag accuracy (correct category? Should a tag have been assigned when one wasn't?)
- Deadline accuracy (correct date math? Appropriate to assign?)
- Information preservation (was anything from the transcript dropped?)
