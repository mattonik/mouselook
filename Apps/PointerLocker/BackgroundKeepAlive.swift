import AVFoundation
import os

/// Keeps the app running in the background for a limited time, so a stream's
/// session survives a quick app switch.
///
/// With the `audio` background mode, iPadOS doesn't suspend an app while it
/// plays audio. The page's own audio isn't enough: WebKit treats a quiet
/// stream as silent and pauses it on entering the background, and the app is
/// then suspended within seconds. So play silence natively, mixed with other
/// apps' audio, until the time is up or the app comes back.
@MainActor
final class BackgroundKeepAlive {
    private let log = Logger(subsystem: "sk.icebear.pointerlocker", category: "KeepAlive")
    private var engine: AVAudioEngine?
    private var timer: Timer?

    /// Start keeping alive for `duration` seconds; `onExpire` runs if the app
    /// is still in the background when the time is up.
    func start(for duration: TimeInterval, onExpire: @escaping () -> Void) {
        stop()
        guard duration > 0 else {
            log.info("Keep-alive off: pausing media now")
            return onExpire()
        }

        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, options: [.mixWithOthers])
        }
        try? session.setActive(true)

        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        let silence = AVAudioSourceNode(format: format) { isSilence, _, _, buffers in
            for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            isSilence.pointee = true
            return noErr
        }
        engine.attach(silence)
        engine.connect(silence, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            self.engine = engine
            log.info("Keep-alive started for \(duration, format: .fixed(precision: 0)) s")
        } catch {
            // Without audio iPadOS suspends us shortly anyway; nothing else to do.
            log.error("Keep-alive audio failed to start: \(error.localizedDescription)")
        }

        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log.info("Keep-alive expired: pausing media")
                self?.stop(releaseAudioSession: true)
                onExpire()
            }
        }
    }

    /// Stop keeping alive. Back in the foreground the page's own audio shares
    /// the session, so it is only released when the time ran out (and media
    /// is paused), letting the system suspend us promptly.
    func stop(releaseAudioSession: Bool = false) {
        guard engine != nil || timer != nil else { return }
        timer?.invalidate()
        timer = nil
        engine?.stop()
        engine = nil
        if releaseAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        log.info("Keep-alive stopped")
    }
}
