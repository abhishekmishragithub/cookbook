# Local setup — run Clicky on your Mac

Voice-OS-agent: a menu-bar app where Hydra starts from the menu bar and runs
your Mac by voice. You only need a **smallest.ai (Hydra) API key**. **No Gemini
key** is needed for this.

## 0. Get the branch
```bash
cd <your cookbook clone>
git fetch ah claude/heyclicky-hydra-speech-clone-1koE4   # 'ah' = your fork remote
git checkout claude/heyclicky-hydra-speech-clone-1koE4
git rebase ah/claude/heyclicky-hydra-speech-clone-1koE4  # if you already had it
cd heyclicky-hydra
```

## 1. (Optional) 2-min voice sanity check in the browser
```bash
cd web && python3 -m http.server 8080   # open http://localhost:8080
```
Pick a source → paste your smallest.ai key → **Connect Hydra** → talk, interrupt
it. Confirms Hydra works before building the app. (This page is just a tester —
the real product is the menu-bar app below.)

## 2. Build the menu-bar app (the product)
The Swift sources are in `macos/HydraClicky/`. Generate the Xcode project with
one command — `project.yml` bakes in the Info.plist keys (LSUIElement, mic +
calendar usage), no App Sandbox, and the deployment target, so there's **no
manual capabilities clicking**:

```bash
brew install xcodegen          # once
cd heyclicky-hydra
xcodegen generate              # creates HydraClicky.xcodeproj
open HydraClicky.xcodeproj
```

In Xcode: select the **HydraClicky** target → **Signing & Capabilities** → pick
your **Team** (the only manual step) → **Run (⌘R)**. A waveform icon appears in
the menu bar → click it → paste your smallest.ai key → **Start listening**.

> Prefer not to install XcodeGen? See the manual wizard steps at the bottom of
> this file. The one-command path above is recommended.

### First-run permission prompts (expected — unavoidable, just click Allow)
- **Microphone** — allow.
- **Automation** — first time it controls Spotify / Reminders / Calendar, macOS
  prompts ("HydraClicky wants to control …"). Allow.
- **Calendar** access for `check_calendar`.
Manage in System Settings → Privacy & Security.

### Try it
"Open Spotify and play Back in Black by AC/DC." · "Drop Spotify to fifty percent."
· "Open my Stripe dashboard in Chrome." · "Set a reminder Saturday 9pm, dinner
with Sharif, and open Reminders." Interrupt it mid-sentence — it should stop.

## 3. Food ordering (Swiggy) — optional, for `order_food`
```bash
cd swiggy-agent
npm install && npx playwright install chromium
node server.mjs                  # http://127.0.0.1:8787, purchase DISABLED
open http://127.0.0.1:8787/login # log into Swiggy once
```
"Order a chicken biryani from Paradise" → builds the cart, **stops at payment**,
Clicky reads it back. To actually place orders (real money):
```bash
SWIGGY_ALLOW_PURCHASE=true node server.mjs
```
Then a spoken "yes, place it" lets Clicky finish. See `docs/SAFETY.md`.

## Troubleshooting
- **No audio / mic** → check the Microphone permission; confirm input device in
  System Settings → Sound. `Mic.swift`/`Player.swift` are the audio plumbing.
- **Actions do nothing** → App Sandbox is probably ON; turn it off. Re-check the
  Automation permission.
- **Spotify plays the wrong song** → pass an exact `spotify:` URI; see the note
  in `Actions.swift` (`play_music`).
- **Swiggy "not_logged_in" / wrong clicks** → hit `/login`; tune `SELECTORS` in
  `swiggy-agent/server.mjs` (Swiggy changes its DOM).

## Continue with Claude Code on your Mac
```bash
cd heyclicky-hydra && claude
```
`CLAUDE.md` auto-loads with full state. You can even hand it the whole build:
*"Run `xcodegen generate`, open/build HydraClicky, and fix any compile errors —
focus on the audio path."* A local session can actually compile and test the
mic/audio, which the cloud session couldn't.

---

## Appendix — manual Xcode setup (if you skip XcodeGen)
1. **Xcode → New → Project → macOS → App** — name `HydraClicky`, SwiftUI, Swift.
2. Delete the generated `ContentView.swift` and `…App.swift`.
3. **Add Files** → everything in `macos/HydraClicky/` **except**
   `SceneGraph.swift` and `VisionLoop.swift`.
4. **Target → Info:** add `Application is agent (UIElement)` = **YES**,
   `Privacy - Microphone Usage Description`, `Privacy - Calendars Usage Description`.
5. **Signing & Capabilities:** **do NOT add App Sandbox** (it blocks
   `osascript`/`NSWorkspace`); pick your Team for automatic signing.
6. **Run (⌘R).**
