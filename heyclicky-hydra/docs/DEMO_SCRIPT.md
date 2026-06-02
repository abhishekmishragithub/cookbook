# The demo script — how to make it go viral

Farza's original Clicky clip hit ~3M views on one relatable "holy shit" moment.
Ours needs the same. The differentiator is **Hydra**, so the demo must show the
things a normal voice assistant *can't* do. Lead with feeling, not features.

## The 45-second cut (record this)

1. **Cold open, no setup (0:00).** Screen already on a real task — e.g. DaVinci
   Resolve mid-edit. Clicky is just *there* by the cursor. No "first, sign in".
2. **It points while it talks (0:05).** You: "how do I make this warmer?"
   Clicky, *as it speaks*, glides to the temperature slider — finger moving with
   the words, like a real teacher. (point_at fires mid-sentence.)
3. **THE MOMENT — barge-in (0:15).** Clicky starts explaining a long step. You
   cut it off: "wait, no — the *other* one." It **stops instantly** and pivots
   to the right thing. This is the shot that makes people rewind. Hold on it.
4. **Proactive (0:25).** You go quiet, fiddle, clearly stuck. Clicky, unprompted:
   "want a hand? you're one click from exporting" → points at Export.
5. **Real-world action (0:35).** "ugh I need a break — play some lo-fi." Clicky:
   "lo-fi beats, you got it" → music actually starts (Phase-5 tool call). Smile,
   end.

## Direction notes
- **Latency is the whole game.** If there's a beat of silence before it talks,
  the magic dies. Tune chunk size / buffering in Phase 0 until replies feel
  instant.
- **Interrupt it on purpose, more than once.** That's the proof it's full-duplex.
- **Keep Clicky's lines short.** Long monologues are boring and make barge-in
  feel like a fight. One idea, then pause.
- **Emotional voice on.** Let Hydra's warmth/humor land — that's what separates
  "tool" from "buddy".
- **One screen, one task.** Don't tour features. Depth on a single relatable
  workflow beats a shallow montage.

## What stands out vs. the original Clicky
| Original Clicky | This (Hydra) |
|---|---|
| Push-to-talk | Always listening, interrupt any time |
| Talk → then point | Points *while* talking |
| Reactive only | Proactively offers help when you're stuck |
| Teaches | Teaches **and acts** (plays music, books, opens things) |
| Stitched STT+LLM+TTS, audible latency | One native S2S model, sub-300ms, emotional |
