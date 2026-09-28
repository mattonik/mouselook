import SwiftUI

struct GetReadyStep: View {
    let profile: ServiceProfile
    let monitor: ReadinessMonitor
    let onStart: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Get ready for \(profile.name)")
                    .font(.largeTitle.bold())
                    .padding(.top, 48)
                    .padding(.bottom, 12)

                StatusRow(symbol: "computermouse", title: mouseTitle, detail: mouseDetail, ok: monitor.mouse != .notConnected,
                          pulsing: monitor.mouse == .moving && !reduceMotion)
                    .accessibilityLabel("Mouse: \(mouseAccessibility)")
                StatusRow(symbol: "keyboard", title: keyboardTitle, detail: keyboardDetail, ok: monitor.keyboard == .connected)
                    .accessibilityLabel("Keyboard: \(keyboardTitle)")
                StatusRow(symbol: "rectangle.inset.filled", title: displayTitle, detail: displayDetail, ok: monitor.display == .fullScreen)
                    .accessibilityLabel("Display: \(displayTitle). \(displayDetail)")

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(profile.setupTips) { tip in
                        InfoRow(symbol: tip.symbol, title: tip.title, detail: tip.detail)
                    }
                    InfoRow(symbol: "escape", title: "Release the mouse",
                            detail: "Hold Esc, press ⌘ + ., or tap the screen with three fingers. To send Esc to the game, press ⌘ + Delete.")
                }
                .padding(.top, 12)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onStart) { Text("Start playing").frame(maxWidth: 320) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }

    private var mouseTitle: String {
        switch monitor.mouse {
        case .notConnected: "Connect a mouse or trackpad"
        case .connected: "Mouse connected"
        case .moving: "Mouse is working"
        }
    }
    private var mouseDetail: String {
        monitor.mouse == .notConnected
            ? "Games need a mouse or trackpad to look around. Touch alone won't work."
            : "Move it and watch the check mark. If it reacts, games can see the mouse too."
    }
    private var mouseAccessibility: String {
        switch monitor.mouse {
        case .notConnected: "not connected"
        case .connected: "connected"
        case .moving: "connected and working"
        }
    }
    private var keyboardTitle: String { monitor.keyboard == .connected ? "Keyboard connected" : "Press any key to check the keyboard" }
    private var keyboardDetail: String {
        monitor.keyboard == .connected ? "Ready for WASD." : "Some keyboards only show up after a key press."
    }
    private var displayTitle: String { monitor.display == .fullScreen ? "Full screen" : "Switch to full screen" }
    private var displayDetail: String {
        monitor.display == .fullScreen
            ? "The mouse can lock to the game."
            : "To lock the mouse, the app needs the full screen. Maximize the window, or turn on Full Screen Apps in Settings ▸ Multitasking & Gestures."
    }
}

private struct StatusRow: View {
    let symbol: String
    let title: String
    let detail: String
    let ok: Bool
    var pulsing = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).frame(width: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .yellow)
                .font(.title2)
                .scaleEffect(pulsing ? 1.25 : 1)
                .animation(.easeOut(duration: 0.15), value: pulsing)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct InfoRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).frame(width: 32).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
