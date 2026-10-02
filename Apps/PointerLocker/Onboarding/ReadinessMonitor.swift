import GameController
import Observation
import QuartzCore

/// Live checks for the Get ready page: is there a mouse (and does it move),
/// a keyboard, and is the app full screen. Inputs are plain methods so the
/// state logic can be tested without hardware; start() wires them to the
/// real devices while the page is visible.
@MainActor
@Observable
final class ReadinessMonitor {
    enum MouseState { case notConnected, connected, moving }
    enum KeyboardState { case notDetected, connected }
    enum DisplayState { case fullScreen, windowed }

    static let movingDuration: TimeInterval = 0.3

    private(set) var mouse: MouseState = .notConnected
    private(set) var keyboard: KeyboardState = .notDetected
    private(set) var display: DisplayState = .fullScreen

    @ObservationIgnored private let hub: MouseEventHub
    @ObservationIgnored private let clock: () -> TimeInterval
    @ObservationIgnored private var mouseCount = 0
    @ObservationIgnored private var lastMove: TimeInterval?
    @ObservationIgnored private var hubToken: MouseEventHub.Token?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timer: Timer?

    /// `hub` defaults to `.shared`, resolved here rather than as a default
    /// argument, which Swift evaluates off the main actor.
    init(hub: MouseEventHub? = nil, clock: @escaping () -> TimeInterval = CACurrentMediaTime) {
        self.hub = hub ?? .shared
        self.clock = clock
    }

    // MARK: Inputs

    func update(mouseCount: Int) {
        self.mouseCount = mouseCount
        if mouseCount == 0 { lastMove = nil }
        refreshMouse(at: clock())
    }

    func mouseMoved(at time: TimeInterval) {
        lastMove = time
        refreshMouse(at: time)
    }

    func tick(at time: TimeInterval) {
        refreshMouse(at: time)
    }

    func update(keyboardConnected: Bool) {
        keyboard = keyboardConnected ? .connected : .notDetected
    }

    /// Full screen if the window covers the screen, in either orientation.
    func update(windowSize: CGSize, screenSize: CGSize) {
        func same(_ a: CGSize, _ b: CGSize) -> Bool { abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1 }
        let swapped = CGSize(width: screenSize.height, height: screenSize.width)
        display = same(windowSize, screenSize) || same(windowSize, swapped) ? .fullScreen : .windowed
    }

    private func refreshMouse(at time: TimeInterval) {
        if let lastMove, time - lastMove < Self.movingDuration {
            mouse = .moving
        } else if mouseCount > 0 || lastMove != nil {
            mouse = .connected
        } else {
            mouse = .notConnected
        }
    }

    // MARK: Live devices

    func start() {
        guard hubToken == nil else { return }
        hubToken = hub.addListener { [weak self] event in
            guard let self else { return }
            switch event {
            case .moved: self.mouseMoved(at: self.clock())
            case .connected, .disconnected: self.update(mouseCount: self.hub.connectedMice)
            case .button, .scrolled: break
            }
        }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(keyboardConnected: GCKeyboard.coalesced != nil) }
            })
        }
        update(mouseCount: hub.connectedMice)
        update(keyboardConnected: GCKeyboard.coalesced != nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self.map { $0.tick(at: $0.clock()) } }
        }
    }

    var isRunning: Bool { hubToken != nil }

    func stop() {
        if let hubToken { hub.remove(hubToken) }
        hubToken = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }
}
