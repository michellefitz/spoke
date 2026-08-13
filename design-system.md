# Spoke Design System

> Voice-first task manager for iOS. Confident, warm, slightly playful.

---

## 1. Brand

**App name:** spoke (lowercase in wordmark, followed by coral dot)
**Tagline:** Your day, dictated.
**Tone:** Confident, warm, slightly playful. Not corporate, not cutesy. Like a friend who's really organized but doesn't make you feel bad about it.

---

## 2. Color

### Primary Accent
| Token | Value | Usage |
|-------|-------|-------|
| **Coral** | `RGB(255, 97, 71)` / `Color(red: 1.0, green: 0.38, blue: 0.28)` | Buttons, active states, mic button, pills, interactive elements |

Coral is the only brand color. Everything else is monochrome via iOS semantic colors.

### Semantic Colors (iOS)
| Token | Usage |
|-------|-------|
| `.label` | Primary text |
| `.secondaryLabel` | Secondary text, metadata, inactive labels |
| `.tertiaryLabel` | Hints, placeholders, very low emphasis |
| `.quaternaryLabel` | Minimal emphasis (delete button icon) |
| `.systemBackground` | Main background |
| `.secondarySystemBackground` | Card surfaces (mode cards, settings rows) |
| `.tertiarySystemFill` | Inactive pill backgrounds, subtle fills |
| `.systemGray2` | Empty state text |
| `.systemGray3` | Illustration strokes, checkbox borders |
| `.systemGray4` | Illustration fills, inactive borders |

### Dark Mode
- **Custom background:** `RGB(18, 18, 18)` / `Color(red: 0.07, green: 0.07, blue: 0.07)` — very dark grey, not pure black
- Coral remains unchanged in dark mode
- All semantic colors adapt automatically
- Toast backgrounds: `Color(white: 0.15).opacity(0.9)` — works in both modes

### Opacity Scale
| Value | Usage |
|-------|-------|
| 0.04 | Subtle shadows |
| 0.06 | Very light coral background (sample card) |
| 0.12 | Light coral background (deadline pills) |
| 0.25 | Coral border on cards |
| 0.35 | Coral shadows, completed text opacity |
| 0.45 | Completed task text |
| 0.5 | Bubble dots, disabled elements |
| 0.6 | Section header text (`label.opacity(0.6)`) |
| 0.75 | Body text on primary, "+Add a step" button |
| 0.8 | Toast background overlay |
| 0.9 | Fade gradient endpoints |
| 0.92 | Waveform background |

---

## 3. Typography

All text uses the system font (San Francisco).

### Scale
| Purpose | Size | Weight | Example |
|---------|------|--------|---------|
| Hero/Splash | 70pt | .medium | "spoke" typewriter |
| Screen heading | 24pt | .semibold | "Say it, we'll sort it" |
| Wordmark | 22pt | .semibold | "spoke" in header |
| Title2 | .title2 | .semibold | "How do you like to get things done?" |
| Task title | 16pt | regular | Task row text |
| Body | 15pt | regular | Value prop copy, descriptions |
| Body small | 14pt | .medium | Buttons, instructions, metadata |
| Labels | 13pt | .medium | Toast text, tag labels |
| Captions | 12pt | .medium | Filter pills, small labels |
| Pills | 11pt | .semibold | Deadline pills, tag pills, badges |
| Micro | 10pt | .semibold | Subtask counter, mini labels |
| Tiny | 9pt | .medium | Section headers in illustrations |
| Illustration | 7-8pt | .bold/.medium | Pills and headers in onboarding cards |

### Text Styles
- **Strikethrough:** completed tasks, checked subtasks
- **Italic:** voice transcription samples
- **ALL CAPS:** all pills (tags, deadlines, filters, placeholders)
- **Monospaced:** debug log values (`.design(.monospaced)`)
- **Kerning:** -1.5 on splash "spoke" wordmark
- **Line spacing:** 2pt on value prop text
- **Tracking:** 0.3pt on metadata pill labels

---

## 4. Spacing

### Padding Scale
| Value | Usage |
|-------|-------|
| 2pt | Optical alignment tweaks |
| 4pt | Internal pill padding, small gaps |
| 6pt | Pill horizontal padding (small) |
| 8pt | Icon padding, medium spacing |
| 10pt | Card internal padding, text field top |
| 12pt | Filter chip horizontal padding |
| 14pt | Sample card padding |
| 16pt | Standard content margin, card padding |
| 20pt | Large vertical spacing, tagline gap |
| 24pt | Section padding, empty state illustration |
| 28pt | Between sample prompt and heading |
| 32pt | CTA button horizontal padding |
| 40pt | Empty state horizontal padding |

### Layout Constants
| Value | Purpose |
|-------|---------|
| 132pt | Bottom voice bar height (includes safe area) |
| 72pt | Voice button diameter |
| 96pt | Voice button pulse diameter |
| 44pt | Minimum tap target (settings button, spacer) |
| 28pt | Settings ellipsis circle size, close button size |

---

## 5. Corner Radius

| Radius | Usage |
|--------|-------|
| 2pt | Cursor, waveform bars |
| 3pt | Metadata pills in illustrations |
| 4pt | Tag pills in task rows |
| 6pt | Deadline/tag pills, small badges |
| 10pt | Illustration inner cards |
| 14pt | Sample voice card |
| 16pt | Major cards, mode selection cards, empty state |
| 27pt | App icon corners (iOS standard) |
| 999pt (Capsule) | Filter pills, CTA buttons, toasts |

---

## 6. Components

### Pills
All pill text is **ALL CAPS**.

| Variant | Font | Text Color | Background | Padding | Shape |
|---------|------|-----------|------------|---------|-------|
| Deadline (active) | 11pt semibold | coral | coral @ 12% | 6h, 4v | rounded 6pt |
| Deadline (completed) | 11pt semibold | coral @ 40% | coral @ 6% | 6h, 4v | rounded 6pt |
| Tag (active) | 11pt semibold | secondaryLabel | tertiarySystemFill | 8h, 4v | rounded 6pt |
| Tag (completed) | 11pt semibold | secondaryLabel @ 40% | tertiarySystemFill @ 50% | 8h, 4v | rounded 6pt |
| Filter (active) | 12pt medium | white | coral | 12h, 6v | capsule |
| Filter (inactive) | 12pt medium | secondaryLabel | tertiarySystemFill | 12h, 6v | capsule |
| Placeholder | 11pt semibold | tertiaryLabel | dashed border (1pt, [3,2]) | 6-8h, 4v | rounded 6pt |
| Subtask count | 10pt semibold | coral (incomplete) / secondaryLabel (done) | tertiarySystemFill | 7h, 3v | capsule |

### Buttons
| Variant | Text | Background | Shape |
|---------|------|-----------|-------|
| Primary CTA | 17pt semibold, white | coral (disabled: systemGray4) | capsule |
| Done/Save | semibold, coral | none | text only |
| Cancel | 15pt, secondaryLabel | none | text only |
| Settings | ellipsis 14pt medium, coral | tertiarySystemFill circle (28pt) | circle in 44pt frame |
| +Add a step | 11pt semibold + 14pt, coral @ 75% | none | text only |

### Toasts
| Property | Value |
|----------|-------|
| Font | 13-14pt medium |
| Text | white |
| Background | `Color(white: 0.15).opacity(0.9)` |
| Padding | 16h, 10v |
| Shape | capsule |
| Position | above mic button (`bottomBarHeight + 8`) |
| Animation in | `.spring(response: 0.35, dampingFraction: 0.8)` |
| Animation out | `.easeOut(duration: 0.3)` |
| Auto-dismiss | 2-4 seconds |

### Checkboxes
| State | Icon | Color | Size |
|-------|------|-------|------|
| Unchecked | `circle` | tertiaryLabel | 16pt (rows), 13pt (subtasks) |
| Checked | `checkmark.circle.fill` | coral | 16pt (rows), 13pt (subtasks) |
| Transition | `.easeInOut(duration: 0.15)` | | |

### Chevrons
| Context | Size | Weight | Color |
|---------|------|--------|-------|
| Task row (has content) | 11pt | .bold | secondaryLabel |
| Completed section | 11pt | .bold | secondaryLabel |
| Rotation | 0 → 90 degrees | | easeInOut(0.25s) |

### Voice Button
| State | Icon | Size | Shadow |
|-------|------|------|--------|
| Idle | mic.fill 22pt | 72pt circle, coral fill | coral @ 40%, radius 12, y: 4 |
| Recording | stop square 18pt, white | 72pt circle + 96pt pulse ring | coral @ 50%, radius 16, y: 4 |
| Processing | spinner arc 24pt | 72pt circle | coral @ 40%, radius 12, y: 4 |
| Disabled (mic denied) | mic.fill 22pt, white @ 50% | 72pt circle, systemGray4 | none |

### Waveform
| Property | Value |
|----------|-------|
| Bar count | 24 per side |
| Bar width | 2.5pt |
| Bar spacing | 2pt |
| Min height | 3pt |
| Max height | 28pt |
| Color | coral @ 70% |
| Corner radius | 1.5pt |
| Animation | spring(0.12, 0.65) |
| Background | systemBackground @ 92% with fade mask |

---

## 7. Icons (SF Symbols)

| Icon | Size | Context |
|------|------|---------|
| `mic.fill` | 22pt, 10pt | Voice button, permission prompt |
| `checkmark.circle.fill` | 16pt, 13pt | Completed checkbox |
| `circle` | 16pt, 13pt | Unchecked checkbox |
| `chevron.right` | 11pt bold | Row disclosure, section expand |
| `ellipsis` | 14pt medium | Settings button |
| `checklist` | 10pt medium | Subtask count badge |
| `trash` | default | Swipe to delete |
| `arrow.uturn.backward` | default | Swipe to uncomplete |
| `plus` | 12pt semibold | Add tag, add step |
| `minus.circle.fill` | 18pt | Remove tag |
| `xmark.circle.fill` | 16pt | Delete focused bullet |
| `wifi.slash` | 12pt semibold | Offline toast |
| `arrow.up.arrow.down` | 14pt medium | Sort toggle |

---

## 8. Shadows

| Context | Color | Radius | Offset |
|---------|-------|--------|--------|
| Voice button (idle) | coral @ 40% | 12 | (0, 4) |
| Voice button (recording) | coral @ 50% | 16 | (0, 4) |
| Onboarding mic dot | coral @ 35% | 5 | (0, 2) |
| Illustration cards | black @ 4% | 3 | (0, 1) |

---

## 9. Animation

### Timing
| Duration | Curve | Usage |
|----------|-------|-------|
| 0.1s | easeInOut | Cursor blink |
| 0.15s | easeInOut | Checkbox toggle, filter pill |
| 0.2s | easeInOut | State transitions, menu changes |
| 0.25s | easeInOut | Section expand/collapse |
| 0.3s | easeOut | Toast dismiss |
| 0.38s | linear | Strikethrough draw (left to right) |
| 0.45s | easeInOut | Onboarding screen transitions |
| 0.5s | easeOut | Fade-in (sample prompt, coaching) |

### Springs
| Response | Damping | Usage |
|----------|---------|-------|
| 0.12 | 0.65 | Waveform bars (fast, responsive) |
| 0.25 | 0.8 | Small UI feedback |
| 0.3 | 0.6 | Scale effects |
| 0.35 | 0.8 | Toast appearance |
| 0.45 | 0.82 | Task insertion |

### Repeating
| Duration | Type | Usage |
|----------|------|-------|
| 0.7s | linear, forever | Spinner rotation |
| 1.1s | easeInOut, autoreverses | Mic button pulse |
| 1.4s | easeOut, forever | Ripple rings (staggered 0.7s) |

### Transitions
- `.opacity` — fade in/out
- `.move(edge: .bottom).combined(with: .opacity)` — toast slide up
- `.scale(scale: 0.98).combined(with: .opacity)` — onboarding screen enter
- `.asymmetric(insertion:, removal:)` — different enter/exit animations

---

## 10. Layout Patterns

### Task List
- Plain list style, no section spacing
- Grouped by time bucket (Added today, Yesterday, This week, Earlier) or deadline bucket (Overdue, Due today, etc.)
- Completed section collapsible with chevron + count
- Filter pills row with horizontal scroll + gradient mask

### Task Row
- HStack: checkbox (16pt) + VStack (title, pills, inline subtasks) + subtask badge + chevron
- Swipe left: complete/uncomplete (green/orange)
- Swipe right: delete with confirmation (red)

### Task Detail
- Half-sheet (`.medium` detent, expandable to `.large`)
- Cancel / Done header
- Title → pills row → description → subtasks → +Add a step
- Fade gradient above voice button
- Voice button at bottom

### Onboarding Flow
- Splash (typewriter) → Mode choice (select + next) → First task (phased animation) → App with coaching toasts

### Empty States
- Wireframe task illustration (circles + bars)
- Single line of copy below
- Main: "Say something. We'll handle the rest."
- Filtered: "Nothing here yet. Speak to add one."

---

## 11. App Icon

- Coral background (full bleed)
- White circular speech bubble (~42% of icon width)
- Coral checkmark inside bubble
- Three descending bubble dots (white, fading opacity)
- No text in icon

---

## 12. Copy Voice

| Context | Style |
|---------|-------|
| Headings | Confident, short ("Say it, we'll sort it") |
| Instructions | Direct, warm ("Tap the mic and say something like:") |
| Success | Brief, celebratory ("Nice! Tap a task to see more.") |
| Errors | Human, reassuring ("Hmm, we didn't catch that.") |
| Empty states | Encouraging, voice-forward ("Say something. We'll handle the rest.") |
| Placeholders | Conversational ("What needs doing?", "Add some detail...") |
| Settings | Factual, concise ("Completed tasks are cleared after 14 days.") |

**Rules:**
- American English throughout
- No exclamation marks except in sample task ("This is a sample task!")
- Pills always ALL CAPS
- Menus and section headers in sentence case
- No emoji in UI (except checkmark in "You're all set ✓")
