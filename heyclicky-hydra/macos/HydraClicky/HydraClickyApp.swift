import SwiftUI

/// Clean menu-bar app. Clicky lives in the menu bar; click it, hit Start, and
/// Hydra connects — full-duplex voice that runs your Mac. No dock icon
/// (set LSUIElement=YES, see docs/SETUP.md).
@main
struct HydraClickyApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            ClickyPanel(app: app)
                .frame(width: 320)
        } label: {
            // Orb changes with state.
            Image(systemName: app.state == .idle ? "mic.slash.circle" : "waveform.circle.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the voice loop and surfaces state to SwiftUI.
final class AppState: ObservableObject {
    @Published var state: AgentState = .idle
    @Published var log: [String] = []
    @Published var apiKey: String = UserDefaults.standard.string(forKey: "hydraKey") ?? ""

    private var orchestrator: Orchestrator?

    var isRunning: Bool { state != .idle }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { add("paste your smallest.ai key first"); return }
        UserDefaults.standard.set(key, forKey: "hydraKey")   // TODO: Keychain

        guard let url = URL(string:
            "wss://api.smallest.ai/waves/v1/s2s?model=hydra&api_key=\(key)") else { return }

        let orch = Orchestrator(hydra: HydraClient(url: url), mic: Mic(), player: Player())
        orch.onState = { [weak self] s in self?.state = s }
        orch.onActivity = { [weak self] line in self?.add(line) }
        orchestrator = orch
        add("connecting…")
        orch.start(systemPrompt: Prompts.system, tools: Prompts.tools, voice: "wren")
    }

    func stop() {
        orchestrator?.stop()
        orchestrator = nil
        state = .idle
        add("stopped")
    }

    private func add(_ s: String) {
        log.append(s)
        if log.count > 50 { log.removeFirst(log.count - 50) }
    }
}

struct ClickyPanel: View {
    @ObservedObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text("Clicky — \(app.state.rawValue)").font(.headline)
                Spacer()
            }

            if !app.isRunning {
                SecureField("smallest.ai API key", text: $app.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            Button(app.isRunning ? "Stop listening" : "Start listening") { app.toggle() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            if app.isRunning {
                Text("Just talk — open apps, play music, set reminders, order food. Interrupt any time.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(app.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 120)

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
        .padding(14)
    }

    private var color: Color {
        switch app.state {
        case .idle: return .gray
        case .connecting: return .yellow
        case .listening: return .green
        case .thinking: return .orange
        case .speaking: return .blue
        }
    }
}
