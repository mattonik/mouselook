import os
import UIKit
import WebKit

/// Keeps a GeForce NOW session alive across an app switch (see
/// BackgroundKeepAlive for how): while queued or loading until the game
/// starts (up to 30 minutes), and while streaming for the chosen time, then
/// pauses all media so the system can suspend the app as usual. Nothing
/// happens outside a session, or when the setting is Off.
@MainActor
final class BackgroundSessionKeeper {
    enum StreamPhase: Int {
        case none = 0     // library, sign-in, …
        case starting = 1 // in the queue or loading the game
        case playing = 2  // a stream is playing
    }

    /// GeForce NOW adds its stream element (#remote-video) when a session
    /// starts (queue, loading) and plays a MediaStream in it once the game
    /// runs; the library and game pages have none.
    static let streamPhaseScript = """
        [...document.querySelectorAll('video')].some(v => v.srcObject && !v.paused) ? 2
            : document.getElementById('remote-video') ? 1 : 0
        """

    static let startingLimit: TimeInterval = 30 * 60
    static let pollInterval: TimeInterval = 5

    private let log = Logger(subsystem: "sk.icebear.pointerlocker", category: "KeepAlive")
    private weak var webView: WKWebView?
    private let keepAlive = BackgroundKeepAlive()
    private var streamWatch: Timer?

    init(webView: WKWebView) {
        self.webView = webView
    }

    func didEnterBackground() {
        streamPhase { [weak self] phase in
            let state = UIApplication.shared.applicationState
            self?.log.info("Entered background: stream phase \(phase.rawValue), app state \(state.rawValue)")
            guard let self, state == .background else { return }
            switch phase {
            case .none: return
            case _ where Settings.backgroundKeepAlive == 0:
                self.webView?.pauseAllMediaPlayback()
            case .playing: self.keepAliveWhilePlaying()
            case .starting:
                self.keepAlive.start(for: Self.startingLimit) { [weak self] in self?.stopWatchingStream() }
                self.watchForStreamStart()
            }
        }
    }

    func willEnterForeground() {
        stopWatchingStream()
        keepAlive.stop()
    }

    private func streamPhase(_ completion: @escaping (StreamPhase) -> Void) {
        guard let webView else { return completion(.none) }
        webView.evaluateJavaScript(Self.streamPhaseScript) { [log] result, error in
            if let error { log.error("Stream phase check failed: \(error.localizedDescription)") }
            completion(StreamPhase(rawValue: result as? Int ?? 0) ?? .none)
        }
    }

    private func keepAliveWhilePlaying() {
        stopWatchingStream()
        keepAlive.start(for: Settings.backgroundKeepAlive) { [weak self] in
            self?.webView?.pauseAllMediaPlayback()
        }
    }

    /// While queued or loading in the background, switch to the playing time
    /// limit once the game starts, or stop if the session goes away.
    private func watchForStreamStart() {
        stopWatchingStream()
        streamWatch = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.streamPhase { [weak self] phase in
                    guard let self, UIApplication.shared.applicationState == .background else { return }
                    switch phase {
                    case .starting: break
                    case .playing: self.keepAliveWhilePlaying()
                    case .none:
                        self.stopWatchingStream()
                        self.keepAlive.stop(releaseAudioSession: true)
                    }
                }
            }
        }
    }

    private func stopWatchingStream() {
        streamWatch?.invalidate()
        streamWatch = nil
    }
}
