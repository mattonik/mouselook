import Foundation

/// User-tunable options, persisted in UserDefaults.
enum Settings {
    static let sensitivityPresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    static var defaults = UserDefaults.standard

    /// The streaming service the user chose (ServiceProfile.id); nil until
    /// they finish onboarding.
    static var serviceID: String? {
        get { defaults.string(forKey: "serviceID") }
        set { defaults.set(newValue, forKey: "serviceID") }
    }

    /// Start page: the service's own unless changed ("Open and set as Home"),
    /// remembered per service.
    static var homeURL: URL {
        get { defaults.url(forKey: "homeURL.\(ServiceProfile.current.id)") ?? ServiceProfile.current.homeURL }
        set { defaults.set(newValue, forKey: "homeURL.\(ServiceProfile.current.id)") }
    }

    /// Multiplier applied to raw GCMouse deltas: always one of the presets,
    /// so the Settings picker shows what's in effect.
    static var sensitivity: Double {
        get { nearestSensitivityPreset(to: defaults.object(forKey: "sensitivity") as? Double ?? 1.0) }
        set { defaults.set(newValue, forKey: "sensitivity") }
    }

    static func nearestSensitivityPreset(to value: Double) -> Double {
        sensitivityPresets.min { abs($0 - value) < abs($1 - value) } ?? 1.0
    }

    /// GameController reports +Y as "up"; the DOM wants +Y as "down", so the
    /// bridge flips it. If vertical look is inverted on your device, toggle this.
    static var invertY: Bool {
        get { defaults.bool(forKey: "invertY") }
        set { defaults.set(newValue, forKey: "invertY") }
    }

    /// Present the service's browser identity (ServiceProfile.identity), e.g.
    /// a Mac for GeForce NOW. Stored under its original key, "spoofDesktop".
    static var useServiceIdentity: Bool {
        get { defaults.object(forKey: "spoofDesktop") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "spoofDesktop") }
    }

    /// Whether pages may use the microphone. `.ask` shows the app's own prompt
    /// once and remembers the answer, instead of WebKit asking every session.
    static var microphone: MicrophoneAccess {
        get { defaults.string(forKey: "microphone").flatMap(MicrophoneAccess.init) ?? .ask }
        set { defaults.set(newValue.rawValue, forKey: "microphone") }
    }

    /// How long a stream keeps running after the app goes to the background
    /// (e.g. to answer a message), in seconds; 0 pauses it right away.
    static var backgroundKeepAlive: TimeInterval {
        get { defaults.object(forKey: "backgroundKeepAlive") as? TimeInterval ?? 300 }
        set { defaults.set(newValue, forKey: "backgroundKeepAlive") }
    }

    static let backgroundKeepAlivePresets: [(title: String, seconds: TimeInterval)] = [
        ("Off", 0), ("1 minute", 60), ("5 minutes", 300), ("15 minutes", 900),
    ]

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
