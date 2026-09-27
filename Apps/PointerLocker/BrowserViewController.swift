import GameController
import UIKit
import WebKit

/// Full-screen WKWebView that gives pages a working Pointer Lock API.
///
/// Lock flow:
///  1. Page calls `element.requestPointerLock()` → polyfill posts `{type: "lock"}`.
///  2. We flip `prefersPointerLocked` (UIKit hides and freezes the system
///     pointer) and activate MouseBridge (raw GCMouse deltas → page).
///  3. Hold Escape, three-finger tap, app switch, navigation or the system
///     dropping the lock → page gets `pointerlockchange` and we release.
final class BrowserViewController: UIViewController {
    private var webView: WKWebView!
    private let bridge = MouseBridge()
    private let menuButton = UIButton(type: .system)
    private let toast = UILabel()

    private var pageWantsLock = false
    private var systemLocked = false
    private var observers: [NSObjectProtocol] = []
    private var hudTimer: Timer?
    #if DEBUG && targetEnvironment(simulator)
    private var debugBridge: DebugBridge?
    #endif

    override var prefersPointerLocked: Bool { pageWantsLock }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { pageWantsLock ? .all : [] }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        hudTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        webView = makeWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        bridge.sensitivity = Float(Settings.sensitivity)
        bridge.invertY = Settings.invertY
        bridge.send = { [weak self] script in
            self?.webView.evaluateJavaScript(script, completionHandler: nil)
        }

        setUpMenuButton()
        setUpToast()
        setUpUnlockGesture()
        observeSystemState()

        #if DEBUG && targetEnvironment(simulator)
        debugBridge = DebugBridge(webView: webView)
        debugBridge?.start()
        #endif

        webView.load(URLRequest(url: Settings.homeURL))
    }

    // MARK: - Web view

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Off: the polyfill emulates the Fullscreen API in-page. Native element
        // fullscreen reparents the web view out of this controller.
        config.preferences.isElementFullscreenEnabled = false
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.userContentController.add(WeakScriptMessageHandler(self), name: "pointerLocker")
        installUserScripts(in: config.userContentController)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true  // Safari ▸ Develop on a Mac, for debugging
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.customUserAgent = Settings.spoofDesktop ? Settings.desktopUserAgent : nil
        return webView
    }

    private func installUserScripts(in controller: WKUserContentController) {
        controller.removeAllUserScripts()
        guard let url = Bundle.main.url(forResource: "pointerlock-polyfill", withExtension: "js"),
              let polyfill = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("pointerlock-polyfill.js missing from bundle")
            return
        }
        let config = "window.__pointerLockerConfig={spoofDesktop:\(Settings.spoofDesktop)};"
        controller.addUserScript(WKUserScript(
            source: config + polyfill,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        if Settings.debugHUD,
           let hudURL = Bundle.main.url(forResource: "debug-hud", withExtension: "js"),
           let hud = try? String(contentsOf: hudURL, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: hud, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        updateHUDTimer()
    }

    /// Push native state (lock, mice, raw input rate) to the debug overlay.
    private func updateHUDTimer() {
        hudTimer?.invalidate()
        hudTimer = nil
        guard Settings.debugHUD else { return }
        var lastCount = bridge.rawEventCount
        var lastTime = CACurrentMediaTime()
        hudTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = CACurrentMediaTime()
                let rate = Int((Double(self.bridge.rawEventCount - lastCount) / (now - lastTime)).rounded())
                lastCount = self.bridge.rawEventCount
                lastTime = now
                let state = "{pageLock:\(self.pageWantsLock),systemLock:\(self.isSystemPointerLocked)," +
                    "mice:\(GCMouse.mice().count),rawRate:\(rate)}"
                self.webView.evaluateJavaScript("window.__pointerLockerHUD&&window.__pointerLockerHUD.native(\(state))")
            }
        }
    }

    /// Rebuild scripts and user agent after a settings change, then reload.
    private func applySettingsAndReload() {
        installUserScripts(in: webView.configuration.userContentController)
        webView.customUserAgent = Settings.spoofDesktop ? Settings.desktopUserAgent : nil
        webView.reload()
    }

    // MARK: - Lock state

    private func setPageLock(_ locked: Bool) {
        guard locked != pageWantsLock else { return }
        pageWantsLock = locked
        bridge.isActive = locked
        setNeedsUpdateOfPrefersPointerLocked()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        UIView.animate(withDuration: 0.2) { self.menuButton.alpha = locked ? 0 : 0.6 }

        if locked {
            // UIKit only honours pointer lock for a full-screen, frontmost scene.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self, self.pageWantsLock, !self.isSystemPointerLocked else { return }
                self.showToast("System pointer not locked — run the app full screen (no Split View / Stage Manager window). Mouse deltas still work.")
            }
        }
    }

    /// Release from the native side; the page is told via `pointerlockchange`.
    private func forceUnlock() {
        guard pageWantsLock else { return }
        webView.evaluateJavaScript("window.__pointerLocker&&window.__pointerLocker.forceUnlock()", completionHandler: nil)
        setPageLock(false)
    }

    private var isSystemPointerLocked: Bool {
        view.window?.windowScene?.pointerLockState?.isLocked ?? false
    }

    private func observeSystemState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIPointerLockState.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let nowLocked = self.isSystemPointerLocked
            // The system dropped a lock we had (e.g. Stage Manager, Slide Over).
            if self.systemLocked && !nowLocked { self.forceUnlock() }
            self.systemLocked = nowLocked
        })
        observers.append(center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.forceUnlock()
        })
    }

    // MARK: - Chrome

    private func setUpMenuButton() {
        menuButton.setImage(UIImage(systemName: "ellipsis.circle.fill"), for: .normal)
        menuButton.tintColor = .white
        menuButton.alpha = 0.6
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.menuItems() ?? [])
        }])
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            menuButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            menuButton.widthAnchor.constraint(equalToConstant: 36),
            menuButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func menuItems() -> [UIMenuElement] {
        let navigation = UIMenu(options: .displayInline, children: [
            UIAction(title: "Back", image: UIImage(systemName: "chevron.backward"),
                     attributes: webView.canGoBack ? [] : .disabled) { [weak self] _ in self?.webView.goBack() },
            UIAction(title: "Reload", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in self?.webView.reload() },
            UIAction(title: "Home", image: UIImage(systemName: "house")) { [weak self] _ in
                self?.webView.load(URLRequest(url: Settings.homeURL))
            },
            UIAction(title: "Open URL…", image: UIImage(systemName: "link")) { [weak self] _ in self?.promptForURL() },
        ])

        let sensitivity = UIMenu(title: "Mouse sensitivity", image: UIImage(systemName: "cursorarrow.motionlines"),
                                 children: Settings.sensitivityPresets.map { value in
            UIAction(title: String(format: "%g×", value), state: Settings.sensitivity == value ? .on : .off) { [weak self] _ in
                Settings.sensitivity = value
                self?.bridge.sensitivity = Float(value)
            }
        })

        let invert = UIAction(title: "Invert vertical", state: Settings.invertY ? .on : .off) { [weak self] _ in
            Settings.invertY.toggle()
            self?.bridge.invertY = Settings.invertY
        }

        let spoof = UIAction(title: "Pretend to be a Mac (reloads)", state: Settings.spoofDesktop ? .on : .off) { [weak self] _ in
            Settings.spoofDesktop.toggle()
            self?.applySettingsAndReload()
        }

        let hud = UIAction(title: "Debug overlay (reloads)", state: Settings.debugHUD ? .on : .off) { [weak self] _ in
            Settings.debugHUD.toggle()
            self?.applySettingsAndReload()
        }

        let help = UIAction(title: "Unlock: hold Esc or three-finger tap", attributes: .disabled) { _ in }

        return [navigation, UIMenu(options: .displayInline, children: [sensitivity, invert, spoof, hud]), help]
    }

    private func promptForURL() {
        let alert = UIAlertController(title: "Open URL", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = self.webView.url?.absoluteString ?? Settings.homeURL.absoluteString
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
            guard let url = Self.normalizedURL(alert.textFields?.first?.text) else { return }
            self?.webView.load(URLRequest(url: url))
        })
        alert.addAction(UIAlertAction(title: "Open and set as Home", style: .default) { [weak self] _ in
            guard let url = Self.normalizedURL(alert.textFields?.first?.text) else { return }
            Settings.homeURL = url
            self?.webView.load(URLRequest(url: url))
        })
        present(alert, animated: true)
    }

    private static func normalizedURL(_ text: String?) -> URL? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        return URL(string: text)
    }

    private func setUpToast() {
        toast.numberOfLines = 0
        toast.textAlignment = .center
        toast.font = .preferredFont(forTextStyle: .footnote)
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        toast.layer.cornerRadius = 10
        toast.layer.masksToBounds = true
        toast.alpha = 0
        toast.isUserInteractionEnabled = false
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
        ])
    }

    private func showToast(_ message: String) {
        toast.text = "  \(message)  "
        UIView.animate(withDuration: 0.2, animations: { self.toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, delay: 4, options: [.beginFromCurrentState]) { self.toast.alpha = 0 }
        }
    }

    private func setUpUnlockGesture() {
        // Touches still reach the app while the pointer is locked, so a
        // three-finger tap is an escape hatch for keyboards without Esc.
        let tap = UITapGestureRecognizer(target: self, action: #selector(threeFingerTap))
        tap.numberOfTouchesRequired = 3
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    @objc private func threeFingerTap() {
        forceUnlock()
    }
}

// MARK: - Page messages

extension BrowserViewController: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }
        switch type {
        case "lock": setPageLock(true)
        case "unlock": setPageLock(false)
        default: break
        }
    }
}

// MARK: - Navigation

extension BrowserViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // A new document starts unlocked.
        setPageLock(false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        setPageLock(false)
        webView.reload()
    }
}

// MARK: - Popups and JavaScript dialogs

extension BrowserViewController: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Sign-in flows open popups and talk back via window.opener, so they
        // need a real child web view built from the supplied configuration.
        let popup = PopupViewController(configuration: configuration, userAgent: webView.customUserAgent)
        present(UINavigationController(rootViewController: popup), animated: true)
        return popup.webView
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presentDialog(alert, orElse: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        presentDialog(alert, orElse: { completionHandler(false) })
    }

    private func presentDialog(_ alert: UIAlertController, orElse fallback: @escaping () -> Void) {
        forceUnlock()
        let host = presentedViewController ?? self
        guard host.presentedViewController == nil else { return fallback() }
        host.present(alert, animated: true)
    }
}

extension BrowserViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Breaks the WKUserContentController → handler retain cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
