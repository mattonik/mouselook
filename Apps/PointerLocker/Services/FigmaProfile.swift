import UIKit

extension ServiceProfile {
    /// Figma's design editor (figma.com). Pointer lock makes number scrubbing
    /// endless: drag a field's label and the value keeps changing past the
    /// edge of the screen.
    static let figma = ServiceProfile(
        id: "figma",
        name: "Figma",
        homeURL: URL(string: "https://www.figma.com/files")!,
        // Not Safari: Figma creates its scrub controls with
        // `disablePointerLock: <browser is Safari>`, detected from the user
        // agent, so as Safari the scrub stops at the screen edge. As Chrome it
        // asks for the lock. Everything else it needs (WebGL 2, WebAssembly
        // SIMD, workers, OffscreenCanvas) is in WebKit.
        identity: .macChrome,
        // No stream to keep alive; Figma saves as you go.
        sessionPhaseScript: "0",
        tagline: "Collaborative design tool",
        artwork: ServiceArtwork(
            symbol: "pencil.and.outline",
            colors: (UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1), UIColor(red: 0.13, green: 0.07, blue: 0.27, alpha: 1))
        ),
        setupTips: [
            SetupTip(
                id: "scrub",
                symbol: "arrow.left.and.right",
                title: "Drag a number's label to change it",
                detail: "The pointer locks while you drag, so the value keeps changing past the edge of the screen. Space + drag moves the canvas."
            ),
            SetupTip(
                id: "session",
                symbol: "person.crop.circle.badge.checkmark",
                title: "Sign in with email and password",
                detail: "Passkeys don't work in this app. You'll stay signed in after the first time."
            ),
        ],
        wording: ServiceWording(
            mouseNeeded: "Figma needs a mouse or trackpad to drag and scrub values. Touch alone won't work.",
            mouseTest: "Move it and watch the check mark. If it reacts, Figma can see the mouse too.",
            keyboardReady: "Ready for shortcuts.",
            lockReady: "The pointer can lock while you drag.",
            release: "Figma lets go when you release the button. If it stays locked, press ⌘ + . or tap the screen with three fingers.",
            start: "Open Figma"
        ),
        category: .create,
        healthChecks: [.scrubLock]
    )
}
