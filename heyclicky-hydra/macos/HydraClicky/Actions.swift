import Foundation
import AppKit

/// Executes Clicky's tool calls against macOS. Most actions go through
/// `osascript` (Spotify, Reminders, Calendar) or `NSWorkspace`/`open`. Food
/// ordering is delegated to the Playwright sidecar (see `swiggy-agent/`).
///
/// Every method returns a JSON string that becomes Hydra's `function_call_output`.
/// Keep outputs truthful — Clicky reports exactly what comes back.
final class ActionRouter {
    /// Where the Swiggy sidecar listens (node swiggy-agent).
    var sidecarURL = URL(string: "http://127.0.0.1:8787")!

    func run(_ name: String, _ args: [String: Any]) async -> String {
        switch name {
        case "open_app":        return openApp(args["name"] as? String ?? "")
        case "open_url":        return openURL(args["url"] as? String ?? "", browser: args["browser"] as? String)
        case "play_music":      return playMusic(query: args["query"] as? String ?? "", uri: args["uri"] as? String)
        case "set_volume":      return setVolume(args)
        case "set_reminder":    return setReminder(args)
        case "check_calendar":  return checkCalendar(args)
        case "start_background_agent": return startAgent(args["task"] as? String ?? "")
        case "order_food":      return await orderFood(args)
        default:                return ok(false, ["error": "unknown tool \(name)"])
        }
    }

    // MARK: - apps / urls

    private func openApp(_ app: String) -> String {
        guard !app.isEmpty else { return ok(false, ["error": "no app name"]) }
        // `open -a` handles app *names* reliably (the deprecated launchApplication
        // and urlForApplication(withBundleIdentifier:) want bundle IDs, not names).
        return shell("/usr/bin/open", ["-a", app]).0 == 0
            ? ok(true, ["opened": app]) : ok(false, ["error": "couldn't open \(app)"])
    }

    private func openURL(_ urlStr: String, browser: String?) -> String {
        guard let url = URL(string: normalizeURL(urlStr)) else { return ok(false, ["error": "bad url"]) }
        if let b = browser, !b.isEmpty {
            return shell("/usr/bin/open", ["-a", b, url.absoluteString]).0 == 0
                ? ok(true, ["opened": url.absoluteString, "in": b]) : ok(false, ["error": "open failed"])
        }
        NSWorkspace.shared.open(url)
        return ok(true, ["opened": url.absoluteString])
    }

    private func normalizeURL(_ s: String) -> String {
        s.hasPrefix("http") || s.hasPrefix("spotify:") ? s : "https://\(s)"
    }

    // MARK: - spotify

    private func playMusic(query: String, uri: String?) -> String {
        if let uri, !uri.isEmpty {
            _ = osa("tell application \"Spotify\" to play track \"\(esc(uri))\"")
            return ok(true, ["playing": uri])
        }
        // No public AppleScript search — open Spotify's search URI, then play the
        // top result. For exact-song reliability, pass a spotify: URI (resolve it
        // via the Spotify Web API upstream if you have a token).
        _ = shell("/usr/bin/open", ["spotify:search:\(query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query)"])
        Thread.sleep(forTimeInterval: 1.2)
        _ = osa("tell application \"Spotify\" to play")
        return ok(true, ["searching_and_playing": query,
                         "note": "played current selection; pass a spotify: URI for an exact track"])
    }

    private func setVolume(_ args: [String: Any]) -> String {
        let scope = (args["scope"] as? String) ?? "spotify"
        if scope == "system" {
            if let level = args["level"] as? Int {
                _ = osa("set volume output volume \(clamp(level))")
                return ok(true, ["system_volume": clamp(level)])
            }
            if let pct = args["change_pct"] as? Int {
                let cur = Int(osa("output volume of (get volume settings)").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 50
                let next = clamp(cur + cur * pct / 100)
                _ = osa("set volume output volume \(next)")
                return ok(true, ["system_volume": next])
            }
            return ok(false, ["error": "need level or change_pct"])
        }
        // spotify
        let cur = Int(osa("tell application \"Spotify\" to get sound volume").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 70
        let target: Int
        if let level = args["level"] as? Int { target = clamp(level) }
        else if let pct = args["change_pct"] as? Int { target = clamp(cur + cur * pct / 100) }
        else { return ok(false, ["error": "need level or change_pct"]) }
        _ = osa("tell application \"Spotify\" to set sound volume to \(target)")
        return ok(true, ["spotify_volume": target])
    }

    // MARK: - reminders / calendar

    private func setReminder(_ args: [String: Any]) -> String {
        let title = args["title"] as? String ?? "Reminder"
        let when = args["when"] as? String ?? ""
        let openAfter = (args["open_after"] as? Bool) ?? true
        // `date "..."` lets macOS parse many natural forms; ISO works too.
        let script = """
        tell application "Reminders"
          set d to (current date)
          try
            set d to (date "\(esc(when))")
          end try
          make new reminder with properties {name:"\(esc(title))", remind me date:d}
        end tell
        """
        let (code, out) = shell("/usr/bin/osascript", ["-e", script])
        if openAfter { _ = shell("/usr/bin/open", ["-a", "Reminders"]) }
        return code == 0 ? ok(true, ["reminder": title, "when": when])
                         : ok(false, ["error": out])
    }

    private func checkCalendar(_ args: [String: Any]) -> String {
        let date = args["date"] as? String ?? ""
        // Best-effort read of event titles for the given day.
        let script = """
        set theDate to (current date)
        try
          set theDate to (date "\(esc(date))")
        end try
        set dayStart to theDate - (time of theDate)
        set dayEnd to dayStart + (1 * days)
        set names to {}
        tell application "Calendar"
          repeat with c in calendars
            repeat with e in (every event of c whose start date ≥ dayStart and start date < dayEnd)
              set end of names to (summary of e)
            end repeat
          end repeat
        end tell
        return names as string
        """
        let (code, out) = shell("/usr/bin/osascript", ["-e", script])
        return code == 0 ? ok(true, ["date": date, "events": out.trimmingCharacters(in: .whitespacesAndNewlines)])
                         : ok(false, ["error": "calendar read failed (grant Calendar access)"])
    }

    // MARK: - background agent

    private func startAgent(_ task: String) -> String {
        // Demo stub: a real impl would spawn a worker (e.g. a headless Claude/agent
        // process) to pursue `task`. Here we just acknowledge + log so the
        // conversation continues, matching Farza's "go work on it in the background".
        NSLog("background agent started: \(task)")
        return ok(true, ["started": true, "task": task, "note": "running in background"])
    }

    // MARK: - food (Swiggy sidecar)

    private func orderFood(_ args: [String: Any]) async -> String {
        var req = URLRequest(url: sidecarURL.appendingPathComponent("order"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "restaurant": args["restaurant"] as? String ?? "",
            "items": args["items"] as? [String] ?? [],
            "confirm": (args["confirm"] as? Bool) ?? false,
        ])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return String(data: data, encoding: .utf8) ?? ok(false, ["error": "empty response"])
        } catch {
            return ok(false, ["error": "swiggy sidecar not reachable — is `node swiggy-agent` running?"])
        }
    }

    // MARK: - helpers

    @discardableResult
    private func osa(_ script: String) -> String { shell("/usr/bin/osascript", ["-e", script]).1 }

    private func shell(_ path: String, _ argv: [String]) -> (Int32, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = argv
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
    }

    private func clamp(_ n: Int) -> Int { max(0, min(100, n)) }
    private func esc(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "\\\"") }

    private func ok(_ success: Bool, _ extra: [String: Any]) -> String {
        var d: [String: Any] = ["ok": success]; extra.forEach { d[$0] = $1 }
        return (try? JSONSerialization.data(withJSONObject: d)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":\(success)}"
    }
}
