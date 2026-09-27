#if DEBUG
import Foundation
import WebKit

/// Debug-only remote JavaScript console, for driving and inspecting the page
/// from the Mac. Long-polls `tools/debug-bridge.py` for a script, runs it as an
/// async function body in the page world, and posts back the JSON-encoded
/// return value. Silently retries when no server runs.
///
/// The simulator uses 127.0.0.1:8766. A device build needs the Mac's address
/// and a shared token baked in (Info.plist PLDebugBridgeURL/Token, from the
/// DEBUG_BRIDGE_URL/TOKEN build settings); without them it stays off.
///
///   python3 tools/debug-bridge.py &
///   curl -s --data-binary 'return document.title' localhost:8766/eval
final class DebugBridge {
    private weak var webView: WKWebView?
    private let base: URL
    private let token: String

    init?(webView: WKWebView) {
        let info = Bundle.main.infoDictionary ?? [:]
        let configured = (info["PLDebugBridgeURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        #if targetEnvironment(simulator)
        guard let base = configured ?? URL(string: "http://127.0.0.1:8766") else { return nil }
        #else
        guard let base = configured else { return nil }
        #endif
        self.webView = webView
        self.base = base
        self.token = info["PLDebugBridgeToken"] as? String ?? ""
    }

    private func makeRequest(_ path: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.setValue(token, forHTTPHeaderField: "X-Bridge-Token")
        return request
    }

    func start() {
        poll()
    }

    private func poll() {
        var request = makeRequest("next")
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
        var request = makeRequest("result")
        request.httpMethod = "POST"
        request.httpBody = Data(reply.utf8)
        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            DispatchQueue.main.async { self?.poll() }
        }.resume()
    }
}
#endif
