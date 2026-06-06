# Safety notes — actions that touch the real world

Clicky executes real actions on your Mac and accounts. Most are safe and
reversible; a few are not. Rules baked into the code:

## Money / irreversible actions need explicit confirmation
- **`order_food`** never pays on the first call. It builds the cart and stops at
  the payment screen (`status: "cart_ready"`). Placing the order requires:
  1. the model passing `confirm: true` (only after a spoken "yes"), **and**
  2. the sidecar env `SWIGGY_ALLOW_PURCHASE=true`.
  The persona (`prompts/system_prompt.md`) is instructed to read the order +
  price back and wait for confirmation before the `confirm:true` call.
- **`start_background_agent`** is a stub. Before wiring it to anything that
  spends money (e.g. a real ad campaign), add the same confirm gate.

## Third-party UI automation (Swiggy)
- This drives **your own** logged-in session — personal-use automation, not
  credential theft or bypass. You log in manually once.
- Selectors break when Swiggy changes its UI. The browser runs **visible** so
  you can watch and intervene; tune `SELECTORS` in `swiggy-agent/server.mjs`.

## macOS permissions
- Spotify/Reminders/Calendar control via `osascript` will prompt for
  **Automation** permission the first time; Calendar reads need Calendar access.
  Grant in System Settings → Privacy & Security.

## Network / keys
- The smallest.ai (Hydra) key and any Gemini key stay local (browser/env) or
  behind the Cloudflare Worker. Don't commit them — `.gitignore` covers the
  profile dir and env files.
