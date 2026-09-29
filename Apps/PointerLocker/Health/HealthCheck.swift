import Foundation

/// A check that watches a service's page for one sign that it changed how it
/// treats this browser (health-checks.js implements them).
enum HealthCheckID: String, CaseIterable {
    case desktopClient = "desktop-client"
    case lockOnClick = "lock-on-click"
    case scrubLock = "scrub-lock"

    /// Settings ▸ Service checks.
    var title: String {
        switch self {
        case .desktopClient: "Desktop version loads"
        case .lockOnClick: "Game asks for the mouse"
        case .scrubLock: "Scrubbing locks the pointer"
        }
    }

    /// The toast shown the first time the check finds a problem in a session.
    /// desktop-client names GeForce NOW because only its profile runs it.
    var problemMessage: String {
        switch self {
        case .desktopClient:
            "GeForce NOW didn't load its desktop version, so the mouse may not lock. Updating Mouselook usually fixes this."
        case .lockOnClick:
            "The game didn't ask for the mouse. Click into the game again. If it keeps happening, copy diagnostics in Settings ▸ Service checks."
        case .scrubLock:
            "Figma didn't lock the pointer while you dragged, so values stop at the screen edge."
        }
    }
}

extension ServiceProfile {
    /// The checks this profile runs. lock-on-click is opt-in: on an arbitrary
    /// page (controller-only games, plain video) a click that doesn't lock is
    /// normal.
    var allHealthChecks: [HealthCheckID] { healthChecks }

    /// Injected before health-checks.js: which checks to run, and how to read
    /// the session phase (a function literal, so no eval under a page's CSP).
    var healthConfigScript: String {
        let ids = allHealthChecks.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        return "window.__mouselookHealth={checks:[\(ids)],phase:()=>(\(sessionPhaseScript))};"
    }
}
