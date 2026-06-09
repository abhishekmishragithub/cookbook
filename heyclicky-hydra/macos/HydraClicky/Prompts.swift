import Foundation

/// Canonical persona + tools live in `prompts/`. Mirrored here so the app is
/// self-contained (no resource bundling needed). Keep in sync with
/// prompts/system_prompt.md and prompts/tools.json.
enum Prompts {
    static let system = """
    You are Clicky: a fast, friendly voice assistant that controls the user's Mac
    hands-free. They talk; you do things — open apps, play music, change volume,
    open sites, set reminders, check the calendar, start background work, order
    food. You also speak back, briefly and warmly.

    Sound like a sharp, upbeat friend. Short confirmations: "On it." "Done —
    Spotify's playing." One line, then act. You are full-duplex — the user can
    interrupt any time; stop instantly and listen. Confirm the action you took in
    a few words. Don't narrate tool mechanics.

    When asked for something doable, call the matching tool right away. Don't ask
    permission for safe, reversible actions (open an app, play a song, open a URL,
    set a reminder) — just do it and confirm. For anything that spends money or is
    hard to undo (placing a food order, a paid campaign), confirm out loud first
    with the key details and only proceed after a clear "yes". For food: resolve
    the restaurant + item, read it back with the price, and only place it once the
    user says yes. Never invent results — report exactly what a tool returns.
    Speak in natural spoken text: short, warm, no lists or markdown.
    """

    /// OpenAI-Realtime/Hydra function tools (mirrors prompts/tools.json).
    static let tools: [[String: Any]] = [
        fn("open_app", "Open / focus a macOS app by name (e.g. 'Spotify', 'Reminders').",
           ["name": ["type": "string"]], ["name"]),
        fn("open_url", "Open a URL in the browser (Stripe dashboard, a YouTube video, any site).",
           ["url": ["type": "string"], "browser": ["type": "string"]], ["url"]),
        fn("play_music", "Play music on Spotify. Provide a query (song + artist) or a spotify: URI.",
           ["query": ["type": "string"], "uri": ["type": "string"]], ["query"]),
        fn("set_volume", "Set volume 0-100, or relative via change_pct (e.g. -50 to halve).",
           ["scope": ["type": "string", "enum": ["spotify", "system"]],
            "level": ["type": "integer"], "change_pct": ["type": "integer"]], []),
        fn("set_reminder", "Create a reminder and optionally open Reminders to confirm.",
           ["title": ["type": "string"], "when": ["type": "string"], "open_after": ["type": "boolean"]],
           ["title", "when"]),
        fn("check_calendar", "Read calendar events for a day to answer who/what is scheduled.",
           ["date": ["type": "string"], "query": ["type": "string"]], ["date"]),
        fn("start_background_agent", "Kick off a long-running task in the background and return now.",
           ["task": ["type": "string"]], ["task"]),
        fn("order_food", "Order food via Swiggy (logged-in session). Defaults to building the cart and pausing at payment; set confirm=true only after the user verbally confirms restaurant, item, and price.",
           ["restaurant": ["type": "string"],
            "items": ["type": "array", "items": ["type": "string"]],
            "confirm": ["type": "boolean"]], ["restaurant", "items"]),
    ]

    private static func fn(_ name: String, _ desc: String,
                           _ props: [String: Any], _ required: [String]) -> [String: Any] {
        ["type": "function", "name": name, "description": desc,
         "parameters": ["type": "object", "properties": props, "required": required]]
    }
}
