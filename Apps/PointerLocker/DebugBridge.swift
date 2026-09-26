#if DEBUG && targetEnvironment(simulator)
import Foundation
import WebKit

/// Simulator-only remote JavaScript console, for driving and inspecting the
/// page from the Mac. Long-polls `tools/debug-bridge.py` on 127.0.0.1:8766 for
/// a script, runs it as an async function body in the page world, and posts
/// back the JSON-encoded return value. Silently retries when no server runs.
///
///   python3 tools/debug-bridge.py &
///   curl -s --data-binary 'return document.title' localhost:8766/eval
final class DebugBridge {
    private weak var webView: WKWebView?
    private let base = URL(string: "http://127.0.0.1:8766")!

    init(webView: WKWebView) {
        self.webView = webView
    }

    func start() {
        poll()
    }

    private func poll() {
        var request = URLRequest(url: base.appendingPathComponent("next"))
        request.timeoutInterval = 60
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode
            guard let data, status == 200, let script = String(data: data, encoding: .utf8) else {
                // 204 = nothing queued, re-poll now; no server = back off.
                let delay: TimeInterval = status == 204 ? 0 : 2
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.poll() }
                return
            }
            DispatchQueue.main.async { self.run(script) }
        }.resume()
    }

    private func run(_ script: String) {
        guard let webView else { return }
        let body = "return JSON.stringify(await (async () => {\n\(script)\n})()) ?? 'undefined';"
        webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { [weak self] result in
            let reply: String
            switch result {
            case .success(let value): reply = value as? String ?? "undefined"
            case .failure(let error): reply = "ERROR: \(error)"
            }
            self?.post(reply)
        }
    }

    private func post(_ reply: String) {
        var request = URLRequest(url: base.appendingPathComponent("result"))
        request.httpMethod = "POST"
        request.httpBody = Data(reply.utf8)
        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            DispatchQueue.main.async { self?.poll() }
        }.resume()
    }
}
#endif
