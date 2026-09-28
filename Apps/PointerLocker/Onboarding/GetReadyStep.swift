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

                StatusRow(symbol: "computermouse", copy: ReadinessCopy.mouse(monitor.mouse), ok: monitor.mouse != .notConnected,
                          pulsing: monitor.mouse == .moving && !reduceMotion)
                StatusRow(symbol: "keyboard", copy: ReadinessCopy.keyboard(monitor.keyboard), ok: monitor.keyboard == .connected)
                StatusRow(symbol: "rectangle.inset.filled", copy: ReadinessCopy.display(monitor.display), ok: monitor.display == .fullScreen)

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
}

private struct StatusRow: View {
    let symbol: String
    let copy: ReadinessCopy.Row
    let ok: Bool
    var pulsing = false
    @ScaledMetric(relativeTo: .title2) private var iconWidth: CGFloat = 32

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).frame(width: iconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title).font(.headline)
                Text(copy.detail).foregroundStyle(.secondary)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.accessibilityLabel)
    }
}

private struct InfoRow: View {
    let symbol: String
    let title: String
    let detail: String
    @ScaledMetric(relativeTo: .title2) private var iconWidth: CGFloat = 32

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).frame(width: iconWidth).foregroundStyle(.tint).accessibilityHidden(true)
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
