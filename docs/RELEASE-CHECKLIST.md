# Release checklist — TestFlight → App Store

Tick things off as you go. The chat walkthrough has the detail; this is the
order of operations.

## One-time setup (~30 min, all in the browser + Xcode)

- [ ] appstoreconnect.apple.com signs in and shows your account (membership active)
- [ ] App Store Connect → Business: accept any pending agreements (free apps
      only need the standard one)
- [ ] Xcode → Settings → Accounts → add your Apple ID → your team appears
- [ ] Spoke target → Signing & Capabilities → "Automatically manage signing"
      on, team selected (do the same for SpokeWidgetExtension)
- [ ] App Store Connect → Apps → **＋ New App**:
      - Name: try `Spoke` — if taken (likely), use `Spoke: To-Do List You Talk To`
      - Bundle ID: `com.michellefitzpatrick.Spoke` (register it when prompted)
      - SKU: `spoke-001` · Language: English (UK or US) · Platform: iOS

## Before every archive

- [ ] `Config.swift` has the real API keys (it's gitignored — archive builds
      use whatever is on your Mac)
- [ ] Bump build number for each new upload (1.0 (1), 1.0 (2), …)

## Upload a build

- [ ] Xcode device selector → **Any iOS Device (arm64)**
- [ ] Product → **Archive** → Organizer opens
- [ ] **Distribute App** → App Store Connect → Upload (accept defaults)
- [ ] Wait for the "processing complete" email (~15–60 min)

## TestFlight

- [ ] Yourself first: TestFlight tab → Internal Testing → create group, add
      your own Apple ID → install via the TestFlight app on your phone
- [ ] Friends & family: External Testing → create group → add build →
      fill in Beta App Information (what to test + your feedback email) →
      first build goes through Beta App Review (~1 day) → then invite by
      email or share the public link
- [ ] Builds expire after 90 days — upload a fresh one before then

## Before the App Store submission (the real gates)

- [ ] **API keys moved out of the app binary** — proxy in place (see chat;
      blocker for public release, fine for TestFlight)
- [ ] Privacy policy page live (must mention: voice audio sent to Deepgram
      for transcription and Anthropic for parsing; calendar data never
      leaves the phone) — URL required by the form
- [ ] Support URL live (landing page is fine)
- [ ] Screenshots: 6.9" (1320×2868) set required; 6.5" reused/scaled
      (storyboard in MARKETING-PLAN.md §7)
- [ ] Listing copy from MARKETING-PLAN.md §7 (title/subtitle/keywords/
      description/promo text)
- [ ] App Privacy questionnaire: Audio Data + Other User Content, not linked
      to identity, no tracking
- [ ] Age rating questionnaire (comes out 4+)
- [ ] Category: Productivity · Price: Free
- [ ] Review notes: no login needed; mic permission required for core flow;
      calendar access optional
- [ ] Featuring nomination submitted (App Store Connect → Growth & Marketing)

## Submit

- [ ] Add build to the version page → Submit for Review
- [ ] Typical review time 24–48h; choose manual release so launch day is
      yours, not Apple's
