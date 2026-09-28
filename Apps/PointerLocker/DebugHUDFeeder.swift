import GameController
import QuartzCore
import WebKit

/// Pushes native state (lock, mice, raw input rate) to the debug overlay
/// (debug-hud.js) twice a second while it's enabled.
@MainActor
final class DebugHUDFeeder {
    private weak var webView: WKWebView?
    private let bridge: MouseBridge
    private let lockState: () -> (page: Bool, system: Bool)
    private var timer: Timer?

    init(webView: WKWebView, bridge: MouseBridge, lockState: @escaping () -> (page: Bool, system: Bool)) {
        self.webView = webView
        self.bridge = bridge
        self.lockState = lockState
    }

    /// Start or stop according to the setting.
    func update() {
        timer?.invalidate()
        timer = nil
        guard Settings.debugHUD else { return }
        var lastCount = bridge.rawEventCount
        var lastTime = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = CACurrentMediaTime()
                let rate = Int((Double(self.bridge.rawEventCount - lastCount) / (now - lastTime)).rounded())
                lastCount = self.bridge.rawEventCount
                lastTime = now
                let lock = self.lockState()
                let state = "{pageLock:\(lock.page),systemLock:\(lock.system),mice:\(GCMouse.mice().count),rawRate:\(rate)}"
                self.webView?.evaluateJavaScript("window.__pointerLockerHUD&&window.__pointerLockerHUD.native(\(state))")
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
