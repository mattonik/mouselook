import WebKit

/// Builds the WKWebView and installs the page scripts.
enum WebViewFactory {
    static let messageHandlerName = "pointerLocker"

    static func makeWebView(messageHandler: WKScriptMessageHandler) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Off: the polyfill emulates the Fullscreen API in-page. Native element
        // fullscreen reparents the web view out of the view controller.
        config.preferences.isElementFullscreenEnabled = false
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.userContentController.add(WeakScriptMessageHandler(messageHandler), name: messageHandlerName)
        installUserScripts(in: config.userContentController)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true  // Safari ▸ Develop on a Mac, for debugging
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        applyUserAgent(to: webView)
        return webView
    }

    /// The polyfill (with its settings) and, if enabled, the debug overlay.
    /// Takes effect on the next page load.
    static func installUserScripts(in controller: WKUserContentController) {
        controller.removeAllUserScripts()
        guard let polyfill = resource("pointerlock-polyfill") else {
            assertionFailure("pointerlock-polyfill.js missing from bundle")
            return
        }
        let config = "window.__pointerLockerConfig={spoofDesktop:\(Settings.spoofDesktop)};"
        controller.addUserScript(WKUserScript(source: config + polyfill, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        if Settings.debugHUD, let hud = resource("debug-hud") {
            controller.addUserScript(WKUserScript(source: hud, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
    }

    static func applyUserAgent(to webView: WKWebView) {
        webView.customUserAgent = Settings.spoofDesktop ? Settings.desktopUserAgent : nil
    }

    private static func resource(_ name: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
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
