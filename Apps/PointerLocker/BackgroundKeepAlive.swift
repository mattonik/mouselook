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
    private let log = Logger(subsystem: "sk.icebear.mouselook", category: "KeepAlive")
    private var engine: AVAudioEngine?
    private var timer: Timer?

    /// Keep alive for `duration` seconds from now; `onExpire` runs if the app
    /// is still in the background when the time is up. Calling it again while
    /// running only resets the time limit.
    func start(for duration: TimeInterval, onExpire: @escaping () -> Void) {
        timer?.invalidate()
        timer = nil
        guard duration > 0 else {
            log.info("Keep-alive off: pausing media now")
            stop(releaseAudioSession: true)
            return onExpire()
        }
        if engine == nil { startSilence() }

        log.info("Keep-alive for \(duration, format: .fixed(precision: 0)) s")
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log.info("Keep-alive expired")
                self?.stop(releaseAudioSession: true)
                onExpire()
            }
        }
    }

    private func startSilence() {
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
        } catch {
            // Without audio iPadOS suspends us shortly anyway; nothing else to do.
            log.error("Keep-alive audio failed to start: \(error.localizedDescription)")
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
