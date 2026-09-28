import GameController

enum MouseEvent: Equatable {
    case moved(dx: Float, dy: Float)
    case button(index: Int, pressed: Bool)
    case scrolled(x: Float, y: Float)
    case connected
    case disconnected
}

typealias MouseEventListener = (MouseEvent) -> Void

/// Owns the GCMouse handlers (each input takes only one) and passes every
/// event to all listeners: MouseBridge for games, the Get ready check for
/// its movement test. Side buttons (back, forward) are buttons 3 and 4.
@MainActor
final class MouseEventHub {
    static let shared = MouseEventHub()

    struct Token: Hashable { fileprivate let id: Int }

    private var listeners: [Int: MouseEventListener] = [:]
    private var nextID = 0
    private var observers: [NSObjectProtocol] = []

    var connectedMice: Int { GCMouse.mice().count }

    init(attachingToMice: Bool = true) {
        guard attachingToMice else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let mouse = note.object as? GCMouse else { return }
            MainActor.assumeIsolated {
                self?.attach(mouse)
                self?.emit(.connected)
            }
        })
        observers.append(center.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit(.disconnected) }
        })
        GCMouse.mice().forEach(attach)
    }

    func addListener(_ listener: @escaping MouseEventListener) -> Token {
        nextID += 1
        listeners[nextID] = listener
        return Token(id: nextID)
    }

    func remove(_ token: Token) {
        listeners[token.id] = nil
    }

    func emit(_ event: MouseEvent) {
        for listener in listeners.values { listener(event) }
    }

    private func attach(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }
        // GCDevice handlers are delivered on `handlerQueue`, main by default.
        mouse.handlerQueue = .main
        input.mouseMovedHandler = { [weak self] _, dx, dy in
            MainActor.assumeIsolated { self?.emit(.moved(dx: dx, dy: dy)) }
        }
        let buttons: [(Int, GCControllerButtonInput?)] = [(0, input.leftButton), (1, input.middleButton), (2, input.rightButton)]
            + (input.auxiliaryButtons ?? []).prefix(2).enumerated().map { (3 + $0.offset, $0.element) }
        for (index, button) in buttons {
            button?.pressedChangedHandler = { [weak self] _, _, pressed in
                MainActor.assumeIsolated { self?.emit(.button(index: index, pressed: pressed)) }
            }
        }
        input.scroll.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.emit(.scrolled(x: x, y: y)) }
        }
    }
}
