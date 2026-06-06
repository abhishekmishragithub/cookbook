# Swiggy ordering sidecar

A localhost helper that lets Clicky order food by voice through **your own
logged-in Swiggy session**. The Mac app's `order_food` tool POSTs here; this
drives Swiggy in a real browser via Playwright.

## Setup
```bash
cd swiggy-agent
npm install
npx playwright install chromium
node server.mjs                      # starts on http://127.0.0.1:8787
```
First run, log in once (the profile persists after that):
```bash
open http://127.0.0.1:8787/login     # sign into Swiggy in the window that opens
```

## How Clicky uses it
- "Order a chicken biryani from Paradise" → tool call `order_food` with
  `confirm:false` → builds the cart, **stops at payment**, Clicky says it's ready.
- You say "yes, place it" → `order_food` with `confirm:true` → it places the order.

## Safety — it will NOT spend money unless you let it
Placing the final order requires **both**:
1. the request has `confirm: true`, **and**
2. the env var `SWIGGY_ALLOW_PURCHASE=true`

```bash
SWIGGY_ALLOW_PURCHASE=true node server.mjs   # only when you're ready to really order
```
Without both, it always pauses at the payment screen and returns
`status: "cart_ready"`. The browser runs **visible** so you can watch and step in.

## Caveats
- Swiggy has no public API — this is UI automation and **selectors drift**. Tune
  `SELECTORS` in `server.mjs` when the site changes.
- Personal-use automation of your own account only.
