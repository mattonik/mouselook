import SwiftUI

/// Welcome → Choose your service → Get ready. Also opened part-way:
/// Settings ▸ Switch service starts at the chooser, Show setup guide at
/// Get ready. Saves nothing itself; onFinish gets the chosen service.
struct OnboardingFlow: View {
    enum Start { case welcome, chooser, getReady(ServiceProfile) }

    private enum Step { case welcome, chooser, getReady(ServiceProfile) }

    let monitor: ReadinessMonitor
    let onFinish: (ServiceProfile) -> Void
    let onCancel: (() -> Void)?
    @State private var step: Step

    init(start: Start, monitor: ReadinessMonitor, onFinish: @escaping (ServiceProfile) -> Void, onCancel: (() -> Void)?) {
        self.monitor = monitor
        self.onFinish = onFinish
        self.onCancel = onCancel
        switch start {
        case .welcome: _step = State(initialValue: .welcome)
        case .chooser: _step = State(initialValue: .chooser)
        case .getReady(let profile): _step = State(initialValue: .getReady(profile))
        }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            switch step {
            case .welcome:
                WelcomeStep { withAnimation { step = .chooser } }
                    .transition(.opacity)
            case .chooser:
                ServiceChooserStep(services: ServiceProfile.selectable) { profile in
                    withAnimation { step = .getReady(profile) }
                }
                .transition(.opacity)
            case .getReady(let profile):
                GetReadyStep(profile: profile, monitor: monitor) { onFinish(profile) }
                    .transition(.opacity)
            }
        }
        // A bar of its own, so scrolled content and large titles don't run
        // under the button.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .accessibilityHint("Closes without changing anything")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(.bar)
            }
        }
        .preferredColorScheme(.dark)
    }
}
