import UIKit
import WebKit

/// Popups, JavaScript dialogs and microphone permission.
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

    /// Answer microphone requests from the saved setting, so WebKit doesn't ask
    /// on every page load. "Ask" shows one prompt and remembers the answer.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard type == .microphone else { return decisionHandler(.prompt) }
        switch Settings.microphone {
        case .allow: decisionHandler(.grant)
        case .deny: decisionHandler(.deny)
        case .ask:
            let alert = UIAlertController(
                title: "Allow \(origin.host) to use the microphone?",
                message: "Used for in-game voice chat. You can change this later under ⋯ ▸ Microphone.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Don't Allow", style: .cancel) { _ in
                Settings.microphone = .deny
                decisionHandler(.deny)
            })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                Settings.microphone = .allow
                decisionHandler(.grant)
            })
            presentDialog(alert, orElse: { decisionHandler(.prompt) })
        }
    }

    /// Dialogs need the pointer back; if something is already presented, give
    /// the page its default answer instead of stacking alerts.
    private func presentDialog(_ alert: UIAlertController, orElse fallback: @escaping () -> Void) {
        forceUnlock()
        let host = presentedViewController ?? self
        guard host.presentedViewController == nil else { return fallback() }
        host.present(alert, animated: true)
    }
}
