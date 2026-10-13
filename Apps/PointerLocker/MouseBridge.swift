import GameController
import QuartzCore

/// Reads raw relative input from GCMouse (via MouseEventHub) and turns it into
/// `window.__pointerLocker.batch([...])` calls for the page.
///
/// Movement is accumulated and flushed once per display frame (one
/// evaluateJavaScript per frame rather than one per HID report, which can be
/// 1000 Hz). Button and wheel events flush immediately, after any pending
/// movement, so ordering is preserved and clicks aren't delayed.
///
/// Only one batch is in flight: while the page is still evaluating the last
/// one (a GC pause, a heavy frame), movement keeps merging and events queue
/// up, so a stall doesn't turn into a burst of stale batches. A batch that
/// never completes stops blocking after `inFlightTimeout`.
@MainActor
final class MouseBridge {
    /// Evaluates the JavaScript in the page and calls the completion when done.
    var send: (_ script: String, _ completion: @escaping () -> Void) -> Void = { _, done in done() }

    /// Only forward input while the page holds the lock.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            pendingX = 0
            pendingY = 0
            queued.removeAll()
            generation += 1         // ignore completions from before
            inFlightSince = nil
            displayLink?.isPaused = !isActive
        }
    }

    static let inFlightTimeout: CFTimeInterval = 0.25
    var clock: () -> CFTimeInterval = CACurrentMediaTime

    var sensitivity: Float = 1
    var invertY = false

    /// Raw GCMouse events received (moves, buttons, scroll), locked or not.
    /// Read and reset by the debug overlay.
    var rawEventCount = 0

    /// DOM wheel pixels per GCMouse scroll unit.
    private let wheelScale: Float = 20

    private var pendingX: Float = 0
    private var pendingY: Float = 0
    private var queued: [String] = []
    private var inFlightSince: CFTimeInterval?
    private var generation = 0
    private var displayLink: CADisplayLink?
    private let hub: MouseEventHub
    private var hubToken: MouseEventHub.Token?

    init(usesDisplayLink: Bool = true, hub: MouseEventHub = .shared) {
        self.hub = hub
        hubToken = hub.addListener { [weak self] event in
            guard let self else { return }
            switch event {
            case .moved(let dx, let dy): self.handleMove(dx: dx, dy: dy)
            case .button(let index, let pressed): self.handleButton(index, pressed: pressed)
            case .scrolled(let x, let y): self.handleScroll(x: x, y: y)
            // The hub releases a lost mouse's buttons as .button events.
            case .connected, .disconnected: break
            }
        }

        guard usesDisplayLink else { return }
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }, selector: #selector(DisplayLinkTarget.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
        if let hubToken { hub.remove(hubToken) }
        hubToken = nil
    }

    // MARK: - Event queueing

    func handleMove(dx: Float, dy: Float) {
        rawEventCount += 1
        guard isActive else { return }
        pendingX += dx * sensitivity
        pendingY += (invertY ? dy : -dy) * sensitivity
    }

    func handleButton(_ index: Int, pressed: Bool) {
        rawEventCount += 1
        guard isActive else { return }
        queueMovement()
        queued.append("[\"b\",\(index),\(pressed)]")
        flush()
    }

    func handleScroll(x: Float, y: Float) {
        rawEventCount += 1
        guard isActive, x != 0 || y != 0 else { return }
        queueMovement()
        queued.append("[\"w\",\(Int((x * wheelScale).rounded())),\(Int((-y * wheelScale).rounded()))]")
        flush()
    }

    /// Emit whole-pixel movement and keep the sub-pixel remainder, so slow
    /// movements aren't lost if the page truncates movementX/Y to integers.
    private func queueMovement() {
        let x = pendingX.rounded(.towardZero)
        let y = pendingY.rounded(.towardZero)
        guard x != 0 || y != 0 else { return }
        pendingX -= x
        pendingY -= y
        queued.append("[\"m\",\(Int(x)),\(Int(y))]")
    }

    /// Send what's pending, unless the page is still busy with the last batch.
    func flush() {
        if let since = inFlightSince, clock() - since < Self.inFlightTimeout { return }
        queueMovement()
        guard !queued.isEmpty else { return }
        let script = "window.__pointerLocker&&window.__pointerLocker.batch([\(queued.joined(separator: ","))])"
        queued.removeAll(keepingCapacity: true)
        inFlightSince = clock()
        let sentGeneration = generation
        send(script) { [weak self] in
            guard let self, self.generation == sentGeneration else { return }
            self.inFlightSince = nil
            self.flush()
        }
    }
}

/// CADisplayLink retains its target; this breaks the cycle with MouseBridge.
private final class DisplayLinkTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func tick() { action() }
}
