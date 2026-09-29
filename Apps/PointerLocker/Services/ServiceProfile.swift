import UIKit

/// What a page should believe it runs on. Streaming services pick their
/// client by device, so an iPad often gets a touch-only client that never
/// asks for pointer lock.
struct BrowserIdentity: Equatable {
    /// Sent as the User-Agent header and `navigator.userAgent`; nil keeps WebKit's.
    var userAgent: String?
    /// `navigator.platform`, on the main thread and inside workers.
    var platform: String?
    /// `navigator.maxTouchPoints`.
    var maxTouchPoints: Int?
    /// Ask WebKit for desktop-class pages.
    var desktopContentMode: Bool

    /// No disguise: an iPad as WebKit presents it.
    static let webKitDefault = BrowserIdentity(userAgent: nil, platform: nil, maxTouchPoints: nil, desktopContentMode: false)

    /// Safari 26.4 on a Mac: the same WebKit as iPadOS 26, so what the page
    /// sees matches what it gets. Pages that check the platform read it from
    /// Web Workers too, hence `platform`.
    static let macSafari = BrowserIdentity(
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/26.4 Safari/605.1.15",
        platform: "MacIntel",
        maxTouchPoints: 0,
        desktopContentMode: true
    )

    /// Chrome on a Mac, for pages that turn off features in Safari that this
    /// app provides (see FigmaProfile.swift). The engine is still WebKit.
    static let macChrome = BrowserIdentity(
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36",
        platform: "MacIntel",
        maxTouchPoints: 0,
        desktopContentMode: true
    )
}

/// Everything specific to one streaming service ("engine"): where it lives,
/// which browser it needs to see, and how to tell that a session is running.
/// The rest of the app (pointer lock, fullscreen emulation, mouse input,
/// background keep-alive) is shared by all of them.
///
/// Adding a service: define a profile in its own file (see
/// GeForceNowProfile.swift) and list it in `all`.
struct ServiceProfile {
    let id: String
    let name: String
    let homeURL: URL
    let identity: BrowserIdentity
    /// JavaScript evaluating to the session phase:
    /// 0 none, 1 queued or loading, 2 streaming (see BackgroundSessionKeeper).
    let sessionPhaseScript: String
    /// One line under the name on the service card.
    let tagline: String
    let artwork: ServiceArtwork
    /// Service-specific items on the Get ready page.
    let setupTips: [SetupTip]
    /// How the Get ready page talks about using it.
    let wording: ServiceWording
    /// Which world it belongs to: Play (games) or Create (tools).
    let category: ServiceCategory
    /// The health checks this service runs (HealthCheck.swift).
    let healthChecks: [HealthCheckID]

    static let all: [ServiceProfile] = [.geforceNow, .figma, .generic]

    /// What onboarding and Settings offer. `generic` stays internal.
    static let selectable: [ServiceProfile] = [.geforceNow, .figma]

    static func profile(id: String) -> ServiceProfile? {
        all.first { $0.id == id }
    }

    typealias ID = String

    /// The profile the app runs with. Falls back to GeForce NOW if nothing (or
    /// something unknown) is stored, so early reads are safe; the launch
    /// decision itself is LaunchRoute's.
    static var current: ServiceProfile {
        Settings.serviceID.flatMap(profile(id:)) ?? .geforceNow
    }

    /// Any page that streams into a <video>; no disguise, no queue detection.
    static let generic = ServiceProfile(
        id: "generic",
        name: "Other website",
        homeURL: URL(string: "about:blank")!,
        identity: .webKitDefault,
        sessionPhaseScript: "[...document.querySelectorAll('video')].some(v => v.srcObject && !v.paused) ? 2 : 0",
        tagline: "Any page that asks for pointer lock",
        artwork: ServiceArtwork(symbol: "globe", colors: (.systemGray, .darkGray)),
        setupTips: [],
        wording: .neutral,
        category: .play,
        healthChecks: []
    )

    /// The identity in effect, given the user's "use browser identity" choice.
    func identity(enabled: Bool) -> BrowserIdentity {
        enabled ? identity : .webKitDefault
    }

    /// Injected before the polyfill (window.__pointerLockerConfig).
    func pageConfigScript(useIdentity: Bool) -> String {
        let effective = identity(enabled: useIdentity)
        var page: [String: Any] = [:]
        if let platform = effective.platform { page["platform"] = platform }
        if let touch = effective.maxTouchPoints { page["maxTouchPoints"] = touch }
        let config: [String: Any] = ["identity": page.isEmpty ? NSNull() : page]
        let data = try! JSONSerialization.data(withJSONObject: config, options: [.sortedKeys, .withoutEscapingSlashes])
        return "window.__pointerLockerConfig=\(String(decoding: data, as: UTF8.self));"
    }
}
