import UIKit

extension ServiceProfile {
    /// NVIDIA GeForce NOW (play.geforcenow.com).
    static let geforceNow = ServiceProfile(
        id: "geforcenow",
        name: "GeForce NOW",
        homeURL: URL(string: "https://play.geforcenow.com")!,
        // GeForce NOW serves its full mouse-and-keyboard client to Safari on
        // a Mac; an iPad gets the touch/PWA flow ("Add to Home Screen"), which
        // never asks for pointer lock. It checks the user agent, touch points,
        // and navigator.platform, the latter from inside a Web Worker.
        //
        // Version 26.4+ matches the iPadOS 26 WebKit underneath, and is the
        // version from which GeForce NOW treats Safari as fully supported: no
        // "partially supported" dialog, and Esc goes straight to the game
        // instead of its ⌘+Delete workaround.
        identity: BrowserIdentity(
            userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/26.4 Safari/605.1.15",
            platform: "MacIntel",
            maxTouchPoints: 0,
            desktopContentMode: true
        ),
        // It adds its stream element (#remote-video) when a session starts
        // (queue, loading) and plays a MediaStream in it once the game runs;
        // the library and game pages have none.
        sessionPhaseScript: """
            [...document.querySelectorAll('video')].some(v => v.srcObject && !v.paused) ? 2
                : document.getElementById('remote-video') ? 1 : 0
            """,
        tagline: "NVIDIA's cloud gaming service",
        artwork: ServiceArtwork(
            symbol: "cloud.bolt.fill",
            colors: (UIColor(red: 0.30, green: 0.62, blue: 0.10, alpha: 1), UIColor(red: 0.07, green: 0.16, blue: 0.05, alpha: 1))
        ),
        setupTips: [
            SetupTip(
                id: "resolution",
                symbol: "rectangle.on.rectangle",
                title: "Set the stream to 1920×1080",
                detail: "In GeForce NOW: Settings ▸ Gameplay ▸ Streaming quality ▸ Custom ▸ Resolution. Some games won't start at the iPad's default size."
            ),
            SetupTip(
                id: "session",
                symbol: "person.crop.circle.badge.checkmark",
                title: "Sign in with a password or email code",
                detail: "Passkeys don't work inside apps. Your sign-in is remembered afterwards."
            ),
        ]
    )
}
