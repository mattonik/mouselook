import UIKit
import WebKit

/// Hosts a `window.open()` popup (e.g. NVIDIA / Microsoft / Google sign-in).
/// WebKit requires the returned web view to use the configuration it passed us.
final class PopupViewController: UIViewController, WKUIDelegate {
    let webView: WKWebView
    /// Messages about this popup's page, shown over it rather than behind it.
    let toast = ToastView()

    init(configuration: WKWebViewConfiguration, userAgent: String?) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent
        webView.isInspectable = true
        super.init(nibName: nil, bundle: nil)
        webView.uiDelegate = self
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        toast.install(in: view)
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
            self?.title = webView.title
        }
    }

    private var titleObservation: NSKeyValueObservation?

    func webViewDidClose(_ webView: WKWebView) {
        dismiss(animated: true)
    }

    // Nested popups: load in place rather than stacking sheets.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
    }
}
