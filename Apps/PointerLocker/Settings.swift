import Foundation

/// User-tunable options, persisted in UserDefaults.
enum Settings {
    static let defaultHomeURL = URL(string: "https://play.geforcenow.com")!

    /// Desktop Safari on macOS. GeForce NOW serves its full mouse+keyboard
    /// client to this; the iPad user agent gets the touch-first PWA flow.
    /// 26.4+ matches the iPadOS 26 WebKit underneath, and is the version from
    /// which GeForce NOW assumes Safari keyboard lock: it drops its "⌘+Delete
    /// sends Esc" workaround and hint and passes Esc straight to the game.
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/26.4 Safari/605.1.15"

    static let sensitivityPresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    private static let defaults = UserDefaults.standard

    static var homeURL: URL {
        get { defaults.url(forKey: "homeURL") ?? defaultHomeURL }
        set { defaults.set(newValue, forKey: "homeURL") }
    }

    /// Multiplier applied to raw GCMouse deltas.
    static var sensitivity: Double {
        get { defaults.object(forKey: "sensitivity") as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: "sensitivity") }
    }

    /// GameController reports +Y as "up"; the DOM wants +Y as "down", so the
    /// bridge flips it. If vertical look is inverted on your device, toggle this.
    static var invertY: Bool {
        get { defaults.bool(forKey: "invertY") }
        set { defaults.set(newValue, forKey: "invertY") }
    }

    /// Send a Mac user agent and report zero touch points, so sites treat the
    /// iPad as a desktop with a mouse.
    static var spoofDesktop: Bool {
        get { defaults.object(forKey: "spoofDesktop") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "spoofDesktop") }
    }

    /// Whether pages may use the microphone. `.ask` shows the app's own prompt
    /// once and remembers the answer, instead of WebKit asking every session.
    static var microphone: MicrophoneAccess {
        get { defaults.string(forKey: "microphone").flatMap(MicrophoneAccess.init) ?? .ask }
        set { defaults.set(newValue.rawValue, forKey: "microphone") }
    }

    /// Show the debug overlay (lock state, input, stream stats).
    static var debugHUD: Bool {
        get { defaults.bool(forKey: "debugHUD") }
        set { defaults.set(newValue, forKey: "debugHUD") }
    }
}

enum MicrophoneAccess: String, CaseIterable {
    case ask, allow, deny

    var title: String {
        switch self {
        case .ask: "Ask"
        case .allow: "Allow"
        case .deny: "Don't Allow"
        }
    }
}
