import SwiftUI

/// Hosts OnboardingFlow, runs the readiness checks while visible, and tells
/// them the window and screen size (for the full-screen row).
final class OnboardingHostingController: UIHostingController<OnboardingFlow> {
    let monitor: ReadinessMonitor

    init(start: OnboardingFlow.Start, onFinish: @escaping (ServiceProfile) -> Void, onCancel: (() -> Void)?) {
        let monitor = ReadinessMonitor()
        self.monitor = monitor
        super.init(rootView: OnboardingFlow(start: start, monitor: monitor, onFinish: onFinish, onCancel: onCancel))
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .systemBackground
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        #if DEBUG
        if ScreenshotScene.current == .getReady {
            monitor.update(mouseCount: 1)
            monitor.update(keyboardConnected: true)
            return
        }
        #endif
        monitor.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        monitor.stop()
    }

    /// Removed as a child (the browser takes over after first launch): UIKit
    /// doesn't always send viewDidDisappear for that, so stop here too.
    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        if parent == nil { monitor.stop() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let window = view.window else { return }
        monitor.update(windowSize: window.bounds.size, screenSize: window.screen.bounds.size)
    }
}
