import GameController
import QuartzCore

/// Reads raw relative input from GCMouse and turns it into
/// `window.__pointerLocker.batch([...])` calls for the page.
///
/// Movement is accumulated and flushed once per display frame (one
/// evaluateJavaScript per frame rather than one per HID report, which can be
/// 1000 Hz). Button and wheel events flush immediately, after any pending
/// movement, so ordering is preserved and clicks aren't delayed.
@MainActor
final class MouseBridge {
    /// Receives the JavaScript to evaluate in the page.
    var send: (String) -> Void = { _ in }

    /// Only forward input while the page holds the lock.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            pendingX = 0
            pendingY = 0
            queued.removeAll()
            displayLink?.isPaused = !isActive
        }
    }

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
    private var displayLink: CADisplayLink?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let mouse = note.object as? GCMouse else { return }
            MainActor.assumeIsolated { self?.attach(mouse) }
        })
        GCMouse.mice().forEach(attach)

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
            MainActor.assumeIsolated { self?.moved(dx: dx, dy: dy) }
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.button(0, pressed) }
        }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.button(1, pressed) }
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.button(2, pressed) }
        }
        // Side buttons (back, forward) are DOM buttons 3 and 4.
        for (offset, aux) in (input.auxiliaryButtons ?? []).prefix(2).enumerated() {
            aux.pressedChangedHandler = { [weak self] _, _, pressed in
                MainActor.assumeIsolated { self?.button(3 + offset, pressed) }
            }
        }
        input.scroll.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.scrolled(x: x, y: y) }
        }
    }

    // MARK: - Event queueing

    private func moved(dx: Float, dy: Float) {
        rawEventCount += 1
        guard isActive else { return }
        pendingX += dx * sensitivity
        pendingY += (invertY ? dy : -dy) * sensitivity
    }

    private func button(_ index: Int, _ pressed: Bool) {
        rawEventCount += 1
        guard isActive else { return }
        queueMovement()
        queued.append("[\"b\",\(index),\(pressed)]")
        flush()
    }

    private func scrolled(x: Float, y: Float) {
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

    private func flush() {
        queueMovement()
        guard !queued.isEmpty else { return }
        let script = "window.__pointerLocker&&window.__pointerLocker.batch([\(queued.joined(separator: ","))])"
        queued.removeAll(keepingCapacity: true)
        send(script)
    }
}

/// CADisplayLink retains its target; this breaks the cycle with MouseBridge.
private final class DisplayLinkTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func tick() { action() }
}
