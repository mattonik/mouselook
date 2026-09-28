import UIKit

/// How a service is pictured in the app: an SF Symbol on a two-colour
/// gradient. Deliberately not the service's own logo or artwork.
struct ServiceArtwork {
    let symbol: String
    let colors: (top: UIColor, bottom: UIColor)
}

/// One service-specific item on the Get ready page.
struct SetupTip: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
}

/// How the Get ready page talks about using a service: games aim and use
/// WASD, a design tool drags and uses shortcuts.
struct ServiceWording: Equatable {
    /// Mouse row, no mouse yet: why one is needed.
    var mouseNeeded: String
    /// Mouse row, mouse connected: how to check it.
    var mouseTest: String
    /// Keyboard row, keyboard connected.
    var keyboardReady: String
    /// Full-screen row, full screen.
    var lockReady: String
    /// "Release the mouse" row.
    var release: String
    /// The button that finishes Get ready.
    var start: String

    /// For a page that isn't a game or a known tool.
    static let neutral = ServiceWording(
        mouseNeeded: "This page needs a mouse or trackpad. Touch alone won't work.",
        mouseTest: "Move it and watch the check mark. If it reacts, the page can see the mouse too.",
        keyboardReady: "Ready to type.",
        lockReady: "The mouse can lock to the page.",
        release: "Hold Esc, press ⌘ + ., or tap the screen with three fingers.",
        start: "Continue"
    )
}
