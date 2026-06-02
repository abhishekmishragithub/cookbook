# Browser demo

A runnable preview of the HeyClicky experience — screen-aware tutoring with a
pointing character — **before** the native Hydra app exists.

- **Demo mode**: uses the bundled `demo-screen.svg` + a canned brain. **Runs
  with zero setup, no API keys.** Great for a quick "see the idea" share.
- **Live mode**: real screen capture (`getDisplayMedia`) → your deployed Worker
  `/tutor` (Gemini) → spoken answer + pointer.

The browser voice (`speechSynthesis`) is a **stand-in for Hydra**. It fakes the
key wow — **barge-in** — by cancelling speech the moment you ask again. The real
thing (true full-duplex, emotional voice) comes from swapping in `HydraClient`.

## Run

```bash
cd heyclicky-hydra/web
python3 -m http.server 8080      # or: npx serve .
# open http://localhost:8080
```

1. Click **▶️ Use demo screenshot** — works immediately. Type "how do I export?"
   and watch Clicky point.
2. For **live**: deploy `../worker`, paste its URL in the box, click
   **🖥️ Share screen**, and ask about whatever's on your screen.

> Mic uses the browser SpeechRecognition API (Chrome/Edge). Screen share needs
> a Chromium-based browser or recent Safari/Firefox.
