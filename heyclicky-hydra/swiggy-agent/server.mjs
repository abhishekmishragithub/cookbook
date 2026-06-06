/**
 * Swiggy ordering sidecar for Clicky.
 *
 * A tiny localhost HTTP server the Mac app (or web demo) calls for `order_food`.
 * It drives YOUR logged-in Swiggy session via Playwright using a *persistent*
 * browser profile, so you log in once (manually) and stay logged in.
 *
 * ── SAFETY (read this) ───────────────────────────────────────────────────────
 *  • Swiggy has no public ordering API; this is UI automation of your own
 *    account. Selectors WILL drift — expect to tune SELECTORS below.
 *  • It NEVER pays automatically. Placing the final order requires BOTH:
 *      (a) the request body has  confirm: true   AND
 *      (b) the env var           SWIGGY_ALLOW_PURCHASE=true
 *    Otherwise it builds the cart and STOPS at the review/payment screen and
 *    returns status "cart_ready" so a human (you, by voice) can confirm.
 *  • The browser runs headed (visible) by default so you can watch / intervene.
 *
 * Run:
 *   cd swiggy-agent && npm install && npx playwright install chromium
 *   node server.mjs               # then POST http://127.0.0.1:8787/order
 *   open http://127.0.0.1:8787/login   # first run: log into Swiggy manually
 */
import http from "node:http";
import { chromium } from "playwright";

const PORT = process.env.PORT || 8787;
const PROFILE_DIR = process.env.SWIGGY_PROFILE || "./.swiggy-profile";
const ALLOW_PURCHASE = process.env.SWIGGY_ALLOW_PURCHASE === "true";

// Best-effort selectors — Swiggy changes these often. Tune here.
const SELECTORS = {
  searchBox: 'input[placeholder*="Search for restaurants" i], input[type="text"]',
  addButton: 'div[role="button"]:has-text("ADD"), button:has-text("ADD")',
  cartButton: 'a[href*="/checkout"], button:has-text("Checkout"), div:has-text("View Cart")',
  placeOrder: 'button:has-text("Place Order"), div[role="button"]:has-text("Place Order")',
};

let browser = null;
async function getContext() {
  if (browser) return browser;
  browser = await chromium.launchPersistentContext(PROFILE_DIR, {
    headless: false,
    viewport: { width: 1280, height: 900 },
  });
  return browser;
}

async function firstPage(ctx) {
  const pages = ctx.pages();
  return pages.length ? pages[0] : await ctx.newPage();
}

/** Build the cart; place the order only when fully authorized. */
async function order({ restaurant, items, confirm }) {
  const ctx = await getContext();
  const page = await firstPage(ctx);

  await page.goto("https://www.swiggy.com/", { waitUntil: "domcontentloaded" });

  // Logged in? Swiggy shows "Login" when not.
  const loggedOut = await page.locator('a:has-text("Login"), button:has-text("Login")').count();
  if (loggedOut > 0) {
    return { ok: false, status: "not_logged_in",
             message: "Open http://127.0.0.1:8787/login and sign in to Swiggy once, then retry." };
  }

  // Search + open the restaurant.
  const search = page.locator(SELECTORS.searchBox).first();
  await search.click().catch(() => {});
  await search.fill(restaurant).catch(() => {});
  await page.keyboard.press("Enter");
  await page.waitForTimeout(2500);
  const restoLink = page.locator(`a:has-text("${restaurant}")`).first();
  if (await restoLink.count()) { await restoLink.click(); await page.waitForTimeout(2500); }

  // Add each item (best-effort: find the dish card, click its ADD).
  const added = [];
  for (const item of items) {
    const card = page.locator(`text=${item}`).first();
    if (await card.count()) {
      const add = page.locator(SELECTORS.addButton).first();
      if (await add.count()) { await add.click().catch(() => {}); added.push(item); await page.waitForTimeout(1200); }
    }
  }

  // Go to cart / checkout — but do NOT pay yet.
  await page.locator(SELECTORS.cartButton).first().click().catch(() => {});
  await page.waitForTimeout(2500);

  const authorized = confirm === true && ALLOW_PURCHASE;
  if (!authorized) {
    return {
      ok: true,
      status: "cart_ready",
      restaurant, added,
      message: confirm && !ALLOW_PURCHASE
        ? "Cart is ready and paused at payment. Set SWIGGY_ALLOW_PURCHASE=true to allow placing orders."
        : "Cart is ready and paused at the payment screen — confirm by voice to place it.",
    };
  }

  // Authorized: place the order with the saved payment method.
  const place = page.locator(SELECTORS.placeOrder).first();
  if (!(await place.count())) {
    return { ok: false, status: "place_button_not_found", restaurant, added,
             message: "Reached checkout but couldn't find Place Order — finish manually." };
  }
  await place.click();
  await page.waitForTimeout(4000);
  return { ok: true, status: "placed", restaurant, added,
           message: "Order placed with your saved payment method." };
}

// ── HTTP server ──────────────────────────────────────────────────────────────
const server = http.createServer(async (req, res) => {
  const send = (code, obj) => {
    res.writeHead(code, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" });
    res.end(JSON.stringify(obj));
  };
  if (req.method === "OPTIONS") return send(204, {});
  if (req.url === "/health") return send(200, { ok: true, allowPurchase: ALLOW_PURCHASE });

  if (req.url === "/login") {
    try { const ctx = await getContext(); const p = await firstPage(ctx);
      await p.goto("https://www.swiggy.com/", { waitUntil: "domcontentloaded" });
      return send(200, { ok: true, message: "Browser opened — log into Swiggy, then close this tab." });
    } catch (e) { return send(500, { ok: false, error: String(e) }); }
  }

  if (req.url === "/order" && req.method === "POST") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", async () => {
      try {
        const args = JSON.parse(body || "{}");
        if (!args.restaurant || !Array.isArray(args.items) || !args.items.length)
          return send(400, { ok: false, error: "restaurant and items[] required" });
        send(200, await order(args));
      } catch (e) { send(500, { ok: false, error: String(e) }); }
    });
    return;
  }
  send(404, { ok: false, error: "not found" });
});

server.listen(PORT, "127.0.0.1", () =>
  console.log(`swiggy-agent on http://127.0.0.1:${PORT}  (purchase ${ALLOW_PURCHASE ? "ENABLED" : "disabled"})`));
