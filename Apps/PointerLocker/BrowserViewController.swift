import Network
import UIKit
import WebKit

/// Full-screen WKWebView that gives pages a working Pointer Lock API.
///
/// Lock flow:
///  1. Page calls `element.requestPointerLock()` → polyfill posts `{type: "lock"}`.
///  2. We flip `prefersPointerLocked` (UIKit hides and freezes the system
///     pointer) and activate MouseBridge (raw GCMouse deltas → page).
///  3. Hold Escape, ⌘., three-finger tap, app switch, navigation or the system
///     dropping the lock → page gets `pointerlockchange` and we release.
///
/// The menu lives in +Menu, popups/dialogs/permissions in +WebUI, and the
/// background keep-alive in BackgroundSessionKeeper.
final class BrowserViewController: UIViewController {
    private(set) var webView: WKWebView!
    let bridge = MouseBridge()
    let menuButton = UIButton(type: .system)
    private let toast = ToastView()
    private let statusOverlay = StatusOverlayView()
    private var crashGuard = CrashLoopGuard()
    private var loadFailure: LoadFailure?
    private let network = NWPathMonitor()
    private var sessionKeeper: BackgroundSessionKeeper!
    private var hudFeeder: DebugHUDFeeder!
    #if DEBUG
    private var debugBridge: DebugBridge?
    #endif

    private var pageWantsLock = false
    private var systemLocked = false
    private var observers: [NSObjectProtocol] = []

    override var prefersPointerLocked: Bool { pageWantsLock }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { pageWantsLock ? .all : [] }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        network.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        webView = WebViewFactory.makeWebView(messageHandler: self)
        webView.navigationDelegate = self
        webView.uiDelegate = self
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
        bridge.send = { [weak self] script, completion in
            guard let webView = self?.webView else { return completion() }
            webView.evaluateJavaScript(script) { _, _ in completion() }
        }

        sessionKeeper = BackgroundSessionKeeper(webView: webView)
        hudFeeder = DebugHUDFeeder(webView: webView, bridge: bridge) { [weak self] in
            (self?.pageWantsLock ?? false, self?.isSystemPointerLocked ?? false)
        }
        hudFeeder.update()

        statusOverlay.frame = view.bounds
        statusOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(statusOverlay)
        setUpMenuButton() // above the overlay, so Back/Home stay reachable
        toast.install(in: view)
        watchNetwork()
        setUpUnlockGesture()
        observeSystemState()

        #if DEBUG
        debugBridge = DebugBridge(webView: webView)
        debugBridge?.start()
        #endif

        webView.load(URLRequest(url: Settings.homeURL))
    }

    /// Rebuild scripts and user agent after a settings change, then reload.
    func applySettingsAndReload() {
        WebViewFactory.installUserScripts(in: webView.configuration.userContentController)
        WebViewFactory.applyIdentity(to: webView)
        hudFeeder.update()
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
                self.toast.show("System pointer not locked — run the app full screen (no Split View / Stage Manager window). Mouse deltas still work.")
            }
        }
    }

    /// Release from the native side; the page is told via `pointerlockchange`.
    func forceUnlock() {
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
        observers.append(center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionKeeper.didEnterBackground()
        })
        observers.append(center.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionKeeper.willEnterForeground()
        })
    }

    // MARK: - Page recovery

    /// A load failed: say why instead of leaving a blank page. When offline,
    /// retry by itself once the connection is back.
    private func handleLoadError(_ error: Error) {
        guard let failure = LoadFailure(error) else { return }
        setPageLock(false)
        loadFailure = failure
        // A DNS or connect error with a working connection means the server is
        // unreachable, not that we're offline.
        if failure.isOffline && network.currentPath.status != .satisfied {
            statusOverlay.show(symbol: "wifi.slash", title: "You're offline",
                               message: "The page will load again when the connection is back.",
                               buttonTitle: "Try Again") { [weak self] in self?.retryLoad() }
        } else {
            statusOverlay.show(symbol: "exclamationmark.triangle", title: "The page couldn't load",
                               message: failure.message,
                               buttonTitle: "Try Again") { [weak self] in self?.retryLoad() }
        }
    }

    private func retryLoad() {
        let url = loadFailure?.url
        loadFailure = nil
        statusOverlay.hide()
        if let url { webView.load(URLRequest(url: url)) } else { webView.reload() }
    }

    private func watchNetwork() {
        network.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async {
                guard let self, self.loadFailure?.isOffline == true, !self.statusOverlay.isHidden else { return }
                self.retryLoad()
            }
        }
        network.start(queue: .global(qos: .utility))
    }

    /// The web content process died (a crash, or the system reclaiming
    /// memory). Reload, unless it keeps happening.
    private func handleContentProcessTermination() {
        setPageLock(false)
        switch crashGuard.recordCrash() {
        case .reload:
            toast.show("The page stopped unexpectedly and was reloaded.")
            webView.reload()
        case .giveUp:
            statusOverlay.show(symbol: "exclamationmark.triangle", title: "The page keeps stopping",
                               message: "This can happen when the iPad runs low on memory. Close other apps, then reload.",
                               buttonTitle: "Reload") { [weak self] in
                guard let self else { return }
                self.crashGuard.reset()
                self.statusOverlay.hide()
                self.webView.reload()
            }
        }
    }

    // MARK: - Releasing the mouse

    private func setUpUnlockGesture() {
        // Touches still reach the app while the pointer is locked, so a
        // three-finger tap is an escape hatch for keyboards without Esc.
        let tap = UITapGestureRecognizer(target: self, action: #selector(threeFingerTap))
        tap.numberOfTouchesRequired = 3
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    /// ⌘. releases the mouse, for keyboards without Esc. As a key command it is
    /// handled here, before the page, so the game never sees it.
    override var keyCommands: [UIKeyCommand]? {
        let unlock = UIKeyCommand(title: "Release Mouse", action: #selector(unlockKeyCommand),
                                  input: ".", modifierFlags: .command)
        unlock.wantsPriorityOverSystemBehavior = true
        return [unlock]
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Only while locked; otherwise ⌘. goes to the page as usual.
        if action == #selector(unlockKeyCommand) { return pageWantsLock }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func unlockKeyCommand() {
        forceUnlock()
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
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        // Follows the identity setting, which can change while running.
        preferences.preferredContentMode = WebViewFactory.identity.desktopContentMode ? .desktop : .recommended
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // A new document starts unlocked, and has loaded: nothing to report.
        setPageLock(false)
        loadFailure = nil
        statusOverlay.hide()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        handleContentProcessTermination()
    }
}

extension BrowserViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
