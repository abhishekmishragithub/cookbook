# The demo script — hands-free voice control (Farza-style)

Modeled on Farza's ~1:44 Clicky demo, but powered by **Hydra**. The whole point:
**you never touch the keyboard.** You talk, it does real things on the Mac, and
talks back — instantly, and you can interrupt it any time.

## The run (record this, one take)

1. **Cold open.** "No hands — ready? Hey Clicky, open Spotify and play *Back in
   Black* by AC/DC." → `play_music` → music starts. ("On it.")
2. **Volume.** "Little loud — drop Spotify to fifty percent." → `set_volume
   {scope:spotify, change_pct:-50}` → volume halves. ("Lowered it to fifty.")
3. **Open a dashboard.** "Open my Stripe dashboard in Chrome." → `open_url`
   → Chrome opens the page.
4. **Background agent.** "Start a Google Ads campaign in the background with
   reasonable defaults — go work on it." → `start_background_agent` → "On it,
   working in the background." (conversation keeps flowing)
5. **Calendar.** "Who's speaking at my YC event Wednesday?" → `check_calendar`
   → it reads the real event back.
6. **Reminder.** "Set a reminder Saturday 9pm — dinner with Sharif — and open
   Reminders to confirm." → `set_reminder {open_after:true}` → Reminders opens
   showing the entry.
7. **THE NEW ONE — order food.** "I'm hungry — order a chicken biryani from
   Paradise on Swiggy." → `order_food {confirm:false}` → builds the cart, pauses
   at payment. Clicky: "Chicken biryani from Paradise, about ₹350, your saved
   payment — want me to place it?" You: "Yep." → `order_food {confirm:true}` →
   "Done — order placed." *(This is the moment people haven't seen before.)*
8. **Close.** "Say hi to everyone watching." → it speaks: "Hey — thanks for
   hanging out." Smile, end.

## Direction notes
- **Latency is everything.** Any dead air before it talks kills the magic. Keep
  Clicky's confirmations to one short line.
- **Interrupt it on purpose** at least once — that's the Hydra proof.
- **The order-food confirmation is a feature, not friction.** Showing it read
  the order back and wait for "yes" is *more* impressive (and trustworthy), not
  less. Don't hide it.
- Have Spotify, Chrome, Reminders, and a logged-in Swiggy session ready
  (`swiggy-agent` running). Do a dry run with `SWIGGY_ALLOW_PURCHASE` unset so
  it stops at payment; flip it on only for the real take.

## Stands out vs. the GPT-Realtime version
| Farza's Clicky | This |
|---|---|
| GPT-Realtime 2.0 | **Hydra** native S2S (smallest.ai) |
| US-centric actions | adds **Swiggy food ordering** (India), confirm-gated |
| — | open-source action layer (`ActionRouter` + sidecar) you can extend |
