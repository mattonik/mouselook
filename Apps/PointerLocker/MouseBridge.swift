import GameController
import QuartzCore

/// Reads raw relative input from GCMouse and turns it into
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
            heldButtons.removeAll() // the page releases its own on unlock
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
    private var heldButtons: [Int] = []
    private var inFlightSince: CFTimeInterval?
    private var generation = 0
    private var displayLink: CADisplayLink?
    private var observers: [NSObjectProtocol] = []

    init(usesDisplayLink: Bool = true) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let mouse = note.object as? GCMouse else { return }
            MainActor.assumeIsolated { self?.attach(mouse) }
        })
        observers.append(center.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDisconnected() }
        })
        GCMouse.mice().forEach(attach)

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
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: - GCMouse

    private func attach(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }
        // GCDevice handlers are delivered on `handlerQueue`, main by default.
        mouse.handlerQueue = .main

        input.mouseMovedHandler = { [weak self] _, dx, dy in
            MainActor.assumeIsolated { self?.handleMove(dx: dx, dy: dy) }
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.handleButton(0, pressed: pressed) }
        }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.handleButton(1, pressed: pressed) }
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.handleButton(2, pressed: pressed) }
        }
        // Side buttons (back, forward) are DOM buttons 3 and 4.
        for (offset, aux) in (input.auxiliaryButtons ?? []).prefix(2).enumerated() {
            aux.pressedChangedHandler = { [weak self] _, _, pressed in
                MainActor.assumeIsolated { self?.handleButton(3 + offset, pressed: pressed) }
            }
        }
        input.scroll.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.handleScroll(x: x, y: y) }
        }
    }

    /// A mouse went away (unplugged, out of battery): release whatever it was
    /// holding, or the game keeps firing or aiming.
    func mouseDisconnected() {
        guard isActive, !heldButtons.isEmpty else { return }
        queueMovement()
        for index in heldButtons { queued.append("[\"b\",\(index),false]") }
        heldButtons.removeAll()
        flush()
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
        if pressed {
            if !heldButtons.contains(index) { heldButtons.append(index) }
        } else {
            heldButtons.removeAll { $0 == index }
        }
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
