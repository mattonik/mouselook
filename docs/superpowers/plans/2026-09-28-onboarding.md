# Onboarding and Service Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** First launch walks the user through Welcome → Choose your service → Get ready, then opens the service; later launches go straight to it, and a new Settings sheet switches services and reopens the guide.

**Architecture:** A UIKit `RootViewController` becomes the window root and shows either a SwiftUI onboarding flow (in a `UIHostingController`) or the existing `BrowserViewController` as a child, forwarding pointer-lock and other system preferences to it. Service presentation data (tagline, artwork, setup tips) is added to `ServiceProfile`. A `MouseEventHub` owns the GCMouse handlers so the readiness check and `MouseBridge` can both listen. Settings move from the ⋯ menu into a SwiftUI `SettingsView` sheet.

**Tech Stack:** Swift 5, UIKit, SwiftUI (iOS 17: `@Observable`), GameController, WebKit, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-28-onboarding-design.md`

## Global Constraints

- Deployment target iOS 17.0; iPad only (`TARGETED_DEVICE_FAMILY: 2`).
- No official logos or artwork of any service; artwork is an SF Symbol plus two gradient colours.
- Nothing is saved to `Settings.serviceID` before the user taps **Start playing**.
- Warnings on Get ready never block **Start playing**.
- Dark appearance for all new screens (`.preferredColorScheme(.dark)` / `overrideUserInterfaceStyle = .dark`).
- Dynamic Type and VoiceOver labels on every new control and status row; Reduce Motion disables the mouse movement pulse.
- New Swift files go under `Apps/PointerLocker/` (XcodeGen picks them up; run `xcodegen -q` after adding files). Tests go under `Tests/PointerLockerTests/`.
- Test command (use for every "run tests" step, adding `-only-testing:` where given):
  `xcodegen -q && xcodebuild test -project PointerLocker.xcodeproj -scheme PointerLocker -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build CODE_SIGNING_ALLOWED=NO`
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Pointer lock after the root changes**: iPadOS asks the window's root view controller; with `RootViewController` as root, locking in a game must still hide the cursor and route GCMouse input. Expect `system ●` in the debug overlay after a lock. (Task 6: forwarding overrides + simulator check.)
2. **"Show setup guide" while a game page is open**: the readiness check must not take the GCMouse handler away from `MouseBridge`; after closing the guide, mouse input in the game still works. (Task 3: hub fan-out test; Task 7: simulator check.)
3. **Rotating or resizing the window while Get ready is open**: the full-screen row follows (portrait ↔ landscape is still full screen; a Stage Manager window is not). (Task 4: swapped-dimensions and windowed tests.)
4. **Switching to the service that is already active**: no rebuild, no session loss, just back to the game. (Task 6: `ServiceSwitch.needsRebuild` test.)
5. **Largest accessibility text size**: Get ready scrolls and **Start playing** stays reachable. (Task 8: simulator check at `accessibility-extra-extra-extra-large`.)

---

### Task 1: Service presentation data

**Files:**
- Create: `Apps/PointerLocker/Services/ServicePresentation.swift`
- Modify: `Apps/PointerLocker/Services/ServiceProfile.swift`
- Modify: `Apps/PointerLocker/Services/GeForceNowProfile.swift`
- Test: `Tests/PointerLockerTests/ServicePresentationTests.swift`

**Interfaces:**
- Produces: `struct ServiceArtwork { let symbol: String; let colors: (top: UIColor, bottom: UIColor) }`, `struct SetupTip: Identifiable { let id: String; let symbol: String; let title: String; let detail: String }`, `ServiceProfile.tagline: String`, `.artwork: ServiceArtwork`, `.setupTips: [SetupTip]`, `static let selectable: [ServiceProfile]`, `static func profile(id: String) -> ServiceProfile?`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PointerLockerTests/ServicePresentationTests.swift
import UIKit
import XCTest
@testable import PointerLocker

final class ServicePresentationTests: XCTestCase {
    func testOnboardingOffersGeForceNowButNotTheGenericProfile() {
        XCTAssertEqual(ServiceProfile.selectable.map(\.id), ["geforcenow"])
    }

    func testEverySelectableServiceCanBePresented() {
        for profile in ServiceProfile.selectable {
            XCTAssertFalse(profile.name.isEmpty, profile.id)
            XCTAssertFalse(profile.tagline.isEmpty, profile.id)
            XCTAssertNotNil(UIImage(systemName: profile.artwork.symbol), "\(profile.id) artwork symbol")
            XCTAssertFalse(profile.setupTips.isEmpty, profile.id)
            for tip in profile.setupTips {
                XCTAssertNotNil(UIImage(systemName: tip.symbol), "\(profile.id) tip \(tip.id) symbol")
                XCTAssertFalse(tip.title.isEmpty)
                XCTAssertFalse(tip.detail.isEmpty)
            }
            XCTAssertEqual(Set(profile.setupTips.map(\.id)).count, profile.setupTips.count, "tip ids unique")
        }
    }

    func testGeForceNowTellsYouToUse1080p() {
        let tip = ServiceProfile.geforceNow.setupTips.first { $0.id == "resolution" }
        XCTAssertEqual(tip?.title, "Set the stream to 1920×1080")
    }

    func testProfilesAreFoundByID() {
        XCTAssertEqual(ServiceProfile.profile(id: "geforcenow")?.name, "GeForce NOW")
        XCTAssertEqual(ServiceProfile.profile(id: "generic")?.id, "generic")
        XCTAssertNil(ServiceProfile.profile(id: "nope"))
    }

    func testServiceIDsAreUnique() {
        XCTAssertEqual(Set(ServiceProfile.all.map(\.id)).count, ServiceProfile.all.count)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command with `-only-testing:PointerLockerTests/ServicePresentationTests`.
Expected: build error — `value of type 'ServiceProfile' has no member 'tagline'` (and `selectable`, `profile(id:)`).

- [ ] **Step 3: Write the implementation**

```swift
// Apps/PointerLocker/Services/ServicePresentation.swift
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
```

In `ServiceProfile.swift`, add three stored properties after `sessionPhaseScript`, the registry helpers, and presentation data for `generic`:

```swift
    /// JavaScript evaluating to the session phase:
    /// 0 none, 1 queued or loading, 2 streaming (see BackgroundSessionKeeper).
    let sessionPhaseScript: String
    /// One line under the name on the service card.
    let tagline: String
    let artwork: ServiceArtwork
    /// Service-specific items on the Get ready page.
    let setupTips: [SetupTip]

    static let all: [ServiceProfile] = [.geforceNow, .generic]

    /// What onboarding and Settings offer. `generic` stays internal.
    static let selectable: [ServiceProfile] = [.geforceNow]

    static func profile(id: String) -> ServiceProfile? {
        all.first { $0.id == id }
    }
```

Replace the `generic` definition with:

```swift
    /// Any page that streams into a <video>; no disguise, no queue detection.
    static let generic = ServiceProfile(
        id: "generic",
        name: "Other website",
        homeURL: URL(string: "about:blank")!,
        identity: .webKitDefault,
        sessionPhaseScript: "[...document.querySelectorAll('video')].some(v => v.srcObject && !v.paused) ? 2 : 0",
        tagline: "Any page that asks for pointer lock",
        artwork: ServiceArtwork(symbol: "globe", colors: (.systemGray, .darkGray)),
        setupTips: []
    )
```

`ServiceProfile.swift` must `import UIKit` (for `UIColor` via `ServiceArtwork`) instead of `import Foundation`.

In `GeForceNowProfile.swift`, add after `sessionPhaseScript: """…"""`:

```swift
        ,
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
```

(The comma goes directly after the closing `"""` of `sessionPhaseScript`.) Change `import Foundation` to `import UIKit` in `GeForceNowProfile.swift`.

- [ ] **Step 4: Run tests to verify they pass**

Run the full test command. Expected: `** TEST SUCCEEDED **` (existing 24 tests + 5 new).

- [ ] **Step 5: Commit**

```bash
git add Apps/PointerLocker/Services Tests/PointerLockerTests/ServicePresentationTests.swift
git commit -m "Service profiles: tagline, artwork and setup tips for onboarding

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: "No service chosen yet" and the launch route

**Files:**
- Modify: `Apps/PointerLocker/Settings.swift:8-20`
- Modify: `Apps/PointerLocker/Services/ServiceProfile.swift` (`current`)
- Create: `Apps/PointerLocker/LaunchRoute.swift`
- Modify: `Tests/PointerLockerTests/ServiceProfileTests.swift` (`testCurrentProfile…`, `testHomeURL…`)
- Test: `Tests/PointerLockerTests/LaunchRouteTests.swift`

**Interfaces:**
- Consumes: `ServiceProfile.selectable`, `ServiceProfile.profile(id:)` (Task 1).
- Produces: `Settings.serviceID: String?`; `enum LaunchRoute: Equatable { case onboarding; case browser(ServiceProfile.ID) }` where `ServiceProfile.ID == String`; `static func LaunchRoute.resolve(serviceID: String?) -> LaunchRoute`; `enum OnboardingCompletion { static func finish(with profile: ServiceProfile) }` (saves `serviceID`).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/PointerLockerTests/LaunchRouteTests.swift
import XCTest
@testable import PointerLocker

@MainActor
final class LaunchRouteTests: XCTestCase {
    private var savedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedDefaults = Settings.defaults
        let suite = "LaunchRouteTests.\(UUID())"
        Settings.defaults = UserDefaults(suiteName: suite)!
        Settings.defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        Settings.defaults = savedDefaults
        super.tearDown()
    }

    func testFirstLaunchShowsOnboarding() {
        XCTAssertNil(Settings.serviceID, "nothing stored on a fresh install")
        XCTAssertEqual(LaunchRoute.resolve(serviceID: Settings.serviceID), .onboarding)
    }

    func testAChosenServiceOpensDirectly() {
        XCTAssertEqual(LaunchRoute.resolve(serviceID: "geforcenow"), .browser("geforcenow"))
    }

    func testUnknownOrInternalServicesGoBackToOnboarding() {
        XCTAssertEqual(LaunchRoute.resolve(serviceID: "removed-in-a-later-version"), .onboarding)
        XCTAssertEqual(LaunchRoute.resolve(serviceID: "generic"), .onboarding, "not user-selectable")
    }

    func testFinishingOnboardingSavesTheChoice() {
        OnboardingCompletion.finish(with: .geforceNow)
        XCTAssertEqual(Settings.serviceID, "geforcenow")
        XCTAssertEqual(LaunchRoute.resolve(serviceID: Settings.serviceID), .browser("geforcenow"))
    }
}
```

In `ServiceProfileTests.swift`, replace `testCurrentProfileDefaultsToGeForceNowAndFallsBackForUnknownIDs` with:

```swift
    func testCurrentProfileFallsBackToGeForceNowWhenNothingOrSomethingUnknownIsStored() {
        XCTAssertNil(Settings.serviceID)
        XCTAssertEqual(ServiceProfile.current.id, "geforcenow")
        Settings.serviceID = "generic"
        XCTAssertEqual(ServiceProfile.current.id, "generic")
        Settings.serviceID = "no-such-service"
        XCTAssertEqual(ServiceProfile.current.id, "geforcenow")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command with `-only-testing:PointerLockerTests/LaunchRouteTests -only-testing:PointerLockerTests/ServiceProfileTests`.
Expected: build errors — `cannot find 'LaunchRoute' in scope`, `'nil' is not compatible with 'String'`.

- [ ] **Step 3: Write the implementation**

In `Settings.swift` replace `serviceID` and `homeURL`:

```swift
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
```

In `ServiceProfile.swift` replace `current`:

```swift
    typealias ID = String

    /// The profile the app runs with. Falls back to GeForce NOW if nothing (or
    /// something unknown) is stored, so early reads are safe; the launch
    /// decision itself is LaunchRoute's.
    static var current: ServiceProfile {
        Settings.serviceID.flatMap(profile(id:)) ?? .geforceNow
    }
```

```swift
// Apps/PointerLocker/LaunchRoute.swift
import Foundation

/// What the app shows when it starts.
enum LaunchRoute: Equatable {
    case onboarding
    case browser(ServiceProfile.ID)

    /// Onboarding until a user-selectable service is stored.
    static func resolve(serviceID: String?) -> LaunchRoute {
        guard let serviceID, ServiceProfile.selectable.contains(where: { $0.id == serviceID }) else {
            return .onboarding
        }
        return .browser(serviceID)
    }
}

/// The only place onboarding's choice is saved: when the user taps
/// Start playing. Choosing a card on its own saves nothing.
enum OnboardingCompletion {
    static func finish(with profile: ServiceProfile) {
        Settings.serviceID = profile.id
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the full test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/PointerLocker/Settings.swift Apps/PointerLocker/Services/ServiceProfile.swift Apps/PointerLocker/LaunchRoute.swift Tests/PointerLockerTests
git commit -m "No service until onboarding is finished; LaunchRoute decides the start screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: MouseEventHub — one GCMouse attachment, many listeners

GCMouse inputs take a single handler per event. Today `MouseBridge` sets them; the Get ready check also needs mouse movement, and "Show setup guide" can open while a game page (and its `MouseBridge`) exists. A hub owns the handlers and fans out.

**Files:**
- Create: `Apps/PointerLocker/MouseEventHub.swift`
- Modify: `Apps/PointerLocker/MouseBridge.swift` (`init`, `attach`, `invalidate`)
- Test: `Tests/PointerLockerTests/MouseEventHubTests.swift`

**Interfaces:**
- Produces: `@MainActor final class MouseEventHub { static let shared; func addListener(_ l: MouseEventListener) -> MouseEventHub.Token; func remove(_ token: Token); func emit(_ event: MouseEvent) }`, `enum MouseEvent: Equatable { case moved(dx: Float, dy: Float); case button(index: Int, pressed: Bool); case scrolled(x: Float, y: Float); case connected; case disconnected }`, `typealias MouseEventListener = (MouseEvent) -> Void`, `var connectedMice: Int`.
- `MouseBridge` keeps `handleMove/handleButton/handleScroll/mouseDisconnected` (Task-free signatures unchanged) and subscribes to the hub.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PointerLockerTests/MouseEventHubTests.swift
import XCTest
@testable import PointerLocker

@MainActor
final class MouseEventHubTests: XCTestCase {
    func testEveryListenerGetsEveryEvent() {
        let hub = MouseEventHub(attachingToMice: false)
        var a: [MouseEvent] = [], b: [MouseEvent] = []
        _ = hub.addListener { a.append($0) }
        _ = hub.addListener { b.append($0) }
        hub.emit(.moved(dx: 1, dy: 2))
        hub.emit(.button(index: 0, pressed: true))
        XCTAssertEqual(a, [.moved(dx: 1, dy: 2), .button(index: 0, pressed: true)])
        XCTAssertEqual(b, a)
    }

    func testARemovedListenerHearsNothingMoreAndOthersKeepListening() {
        let hub = MouseEventHub(attachingToMice: false)
        var bridge: [MouseEvent] = [], guide: [MouseEvent] = []
        _ = hub.addListener { bridge.append($0) }
        let guideToken = hub.addListener { guide.append($0) }
        hub.emit(.moved(dx: 1, dy: 0))
        hub.remove(guideToken) // closing "Show setup guide"
        hub.emit(.moved(dx: 2, dy: 0))
        XCTAssertEqual(guide, [.moved(dx: 1, dy: 0)])
        XCTAssertEqual(bridge, [.moved(dx: 1, dy: 0), .moved(dx: 2, dy: 0)], "the game keeps its mouse")
    }

    func testMouseBridgeFollowsTheHub() {
        let hub = MouseEventHub(attachingToMice: false)
        let bridge = MouseBridge(usesDisplayLink: false, hub: hub)
        var sent: [String] = []
        bridge.send = { script, done in sent.append(script); done() }
        bridge.isActive = true
        hub.emit(.moved(dx: 3, dy: 0))
        bridge.flush()
        hub.emit(.button(index: 0, pressed: true))
        XCTAssertEqual(sent.count, 2)
        XCTAssertTrue(sent[0].contains(#"["m",3,0]"#))
        XCTAssertTrue(sent[1].contains(#"["b",0,true]"#))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command with `-only-testing:PointerLockerTests/MouseEventHubTests`.
Expected: build error — `cannot find 'MouseEventHub' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Apps/PointerLocker/MouseEventHub.swift
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
```

In `MouseBridge.swift`:
1. Replace the `observers` property with `private var hubToken: MouseEventHub.Token?` and `private let hub: MouseEventHub`.
2. Replace `init(usesDisplayLink:)`'s notification/attach code with a hub subscription:

```swift
    init(usesDisplayLink: Bool = true, hub: MouseEventHub = .shared) {
        self.hub = hub
        hubToken = hub.addListener { [weak self] event in
            guard let self else { return }
            switch event {
            case .moved(let dx, let dy): self.handleMove(dx: dx, dy: dy)
            case .button(let index, let pressed): self.handleButton(index, pressed: pressed)
            case .scrolled(let x, let y): self.handleScroll(x: x, y: y)
            case .disconnected: self.mouseDisconnected()
            case .connected: break
            }
        }

        guard usesDisplayLink else { return }
        // (display link setup unchanged)
```

3. Delete `private func attach(_ mouse: GCMouse)` from `MouseBridge`.
4. `invalidate()` becomes:

```swift
    func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
        if let hubToken { hub.remove(hubToken) }
        hubToken = nil
    }
```

5. Update the doc comment: "Reads raw relative input from GCMouse (via MouseEventHub) and turns it into…".

- [ ] **Step 4: Run tests to verify they pass**

Run the full test command. Expected: `** TEST SUCCEEDED **` (existing MouseBridgeTests still pass; they call `handleMove` etc. directly).

- [ ] **Step 5: Commit**

```bash
git add Apps/PointerLocker/MouseEventHub.swift Apps/PointerLocker/MouseBridge.swift Tests/PointerLockerTests/MouseEventHubTests.swift
git commit -m "MouseEventHub: one GCMouse attachment shared by all listeners

GCMouse inputs take one handler each. The Get ready check needs mouse
movement too, and can open while a game's MouseBridge is listening, so a hub
now owns the handlers and fans events out.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: ReadinessMonitor

**Files:**
- Create: `Apps/PointerLocker/Onboarding/ReadinessMonitor.swift`
- Test: `Tests/PointerLockerTests/ReadinessMonitorTests.swift`

**Interfaces:**
- Consumes: `MouseEventHub` (Task 3).
- Produces: `@MainActor @Observable final class ReadinessMonitor` with `enum MouseState { notConnected, connected, moving }`, `enum KeyboardState { notDetected, connected }`, `enum DisplayState { fullScreen, windowed }`; read-only `mouse`, `keyboard`, `display`; inputs `update(mouseCount:)`, `mouseMoved(at:)`, `tick(at:)`, `update(keyboardConnected:)`, `update(windowSize:screenSize:)`; live wiring `start()`, `stop()`; `static let movingDuration: TimeInterval = 0.3`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PointerLockerTests/ReadinessMonitorTests.swift
import XCTest
@testable import PointerLocker

@MainActor
final class ReadinessMonitorTests: XCTestCase {
    func testMouseStates() {
        let monitor = ReadinessMonitor(hub: MouseEventHub(attachingToMice: false))
        XCTAssertEqual(monitor.mouse, .notConnected)
        monitor.update(mouseCount: 1)
        XCTAssertEqual(monitor.mouse, .connected)
        monitor.mouseMoved(at: 10)
        XCTAssertEqual(monitor.mouse, .moving)
        monitor.tick(at: 10.1)
        XCTAssertEqual(monitor.mouse, .moving, "still within the pulse")
        monitor.tick(at: 10 + ReadinessMonitor.movingDuration)
        XCTAssertEqual(monitor.mouse, .connected)
    }

    func testUnpluggingWhileMovingSaysNotConnected() {
        let monitor = ReadinessMonitor(hub: MouseEventHub(attachingToMice: false))
        monitor.update(mouseCount: 1)
        monitor.mouseMoved(at: 0)
        monitor.update(mouseCount: 0)
        XCTAssertEqual(monitor.mouse, .notConnected)
        monitor.tick(at: 1)
        XCTAssertEqual(monitor.mouse, .notConnected)
    }

    func testMovementCountsAsAConnectedMouse() {
        // A trackpad can report deltas before GCMouse.mice() lists it.
        let monitor = ReadinessMonitor(hub: MouseEventHub(attachingToMice: false))
        monitor.mouseMoved(at: 0)
        XCTAssertEqual(monitor.mouse, .moving)
        monitor.tick(at: 1)
        XCTAssertEqual(monitor.mouse, .connected)
    }

    func testMovementArrivesThroughTheHub() {
        let hub = MouseEventHub(attachingToMice: false)
        let monitor = ReadinessMonitor(hub: hub, clock: { 5 })
        monitor.start()
        hub.emit(.moved(dx: 1, dy: 0))
        XCTAssertEqual(monitor.mouse, .moving)
        monitor.stop()
        monitor.tick(at: 6)
        hub.emit(.moved(dx: 1, dy: 0))
        XCTAssertEqual(monitor.mouse, .connected, "stopped: no longer listening")
    }

    func testKeyboard() {
        let monitor = ReadinessMonitor(hub: MouseEventHub(attachingToMice: false))
        XCTAssertEqual(monitor.keyboard, .notDetected)
        monitor.update(keyboardConnected: true)
        XCTAssertEqual(monitor.keyboard, .connected)
    }

    func testFullScreenInEitherOrientationButNotInAWindow() {
        let monitor = ReadinessMonitor(hub: MouseEventHub(attachingToMice: false))
        let screen = CGSize(width: 1024, height: 1366)
        monitor.update(windowSize: screen, screenSize: screen)
        XCTAssertEqual(monitor.display, .fullScreen)
        monitor.update(windowSize: CGSize(width: 1366, height: 1024), screenSize: screen)
        XCTAssertEqual(monitor.display, .fullScreen, "rotated")
        monitor.update(windowSize: CGSize(width: 1366, height: 1023.5), screenSize: screen)
        XCTAssertEqual(monitor.display, .fullScreen, "sub-point rounding")
        monitor.update(windowSize: CGSize(width: 944, height: 1260), screenSize: screen)
        XCTAssertEqual(monitor.display, .windowed, "iPadOS 26 window / Stage Manager")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command with `-only-testing:PointerLockerTests/ReadinessMonitorTests`.
Expected: build error — `cannot find 'ReadinessMonitor' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Apps/PointerLocker/Onboarding/ReadinessMonitor.swift
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

    init(hub: MouseEventHub = .shared, clock: @escaping () -> TimeInterval = CACurrentMediaTime) {
        self.hub = hub
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

    func stop() {
        if let hubToken { hub.remove(hubToken) }
        hubToken = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }
}
```

Note `update(mouseCount:)` in `start()` uses the real `hub.connectedMice`; in `testMovementArrivesThroughTheHub` the test hub has no attached mice, so `GCMouse.mice()` is read. On a CI simulator that is 0, so the state after `stop()`/`tick(6)` is `.connected` only because `lastMove` is set — which is what the test asserts.

- [ ] **Step 4: Run tests to verify they pass**

Run the full test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/PointerLocker/Onboarding Tests/PointerLockerTests/ReadinessMonitorTests.swift
git commit -m "ReadinessMonitor: live mouse, keyboard and full-screen checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Onboarding screens (SwiftUI)

**Files:**
- Create: `Apps/PointerLocker/Onboarding/OnboardingFlow.swift`
- Create: `Apps/PointerLocker/Onboarding/WelcomeStep.swift`
- Create: `Apps/PointerLocker/Onboarding/ServiceChooserStep.swift`
- Create: `Apps/PointerLocker/Onboarding/GetReadyStep.swift`
- Create: `Apps/PointerLocker/Onboarding/OnboardingHostingController.swift`

**Interfaces:**
- Consumes: `ServiceProfile.selectable`, `.tagline`, `.artwork`, `.setupTips` (Task 1); `ReadinessMonitor` (Task 4).
- Produces: `struct OnboardingFlow: View` with `init(start: OnboardingFlow.Start, monitor: ReadinessMonitor, onFinish: @escaping (ServiceProfile) -> Void, onCancel: (() -> Void)?)` and `enum Start { case welcome, chooser, getReady(ServiceProfile) }`; `final class OnboardingHostingController: UIHostingController<OnboardingFlow>` with `init(start:onFinish:onCancel:)` (owns the monitor, starts/stops it, feeds window and screen size).

No unit tests: the state is in `ReadinessMonitor` (tested) and the choice is saved by `OnboardingCompletion` (tested). This task is verified by building and by screenshots in Task 6.

- [ ] **Step 1: Write the flow container**

```swift
// Apps/PointerLocker/Onboarding/OnboardingFlow.swift
import SwiftUI

/// Welcome → Choose your service → Get ready. Also opened part-way:
/// Settings ▸ Switch service starts at the chooser, Show setup guide at
/// Get ready. Saves nothing itself; onFinish gets the chosen service.
struct OnboardingFlow: View {
    enum Start { case welcome, chooser, getReady(ServiceProfile) }

    private enum Step { case welcome, chooser, getReady(ServiceProfile) }

    let monitor: ReadinessMonitor
    let onFinish: (ServiceProfile) -> Void
    let onCancel: (() -> Void)?
    @State private var step: Step

    init(start: Start, monitor: ReadinessMonitor, onFinish: @escaping (ServiceProfile) -> Void, onCancel: (() -> Void)?) {
        self.monitor = monitor
        self.onFinish = onFinish
        self.onCancel = onCancel
        switch start {
        case .welcome: _step = State(initialValue: .welcome)
        case .chooser: _step = State(initialValue: .chooser)
        case .getReady(let profile): _step = State(initialValue: .getReady(profile))
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch step {
            case .welcome:
                WelcomeStep { withAnimation { step = .chooser } }
                    .transition(.opacity)
            case .chooser:
                ServiceChooserStep(services: ServiceProfile.selectable) { profile in
                    withAnimation { step = .getReady(profile) }
                }
                .transition(.opacity)
            case .getReady(let profile):
                GetReadyStep(profile: profile, monitor: monitor) { onFinish(profile) }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .padding()
                    .accessibilityHint("Closes without changing anything")
            }
        }
        .preferredColorScheme(.dark)
    }
}
```

- [ ] **Step 2: Write Welcome and the service chooser**

```swift
// Apps/PointerLocker/Onboarding/WelcomeStep.swift
import SwiftUI

struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("PointerLocker")
                .font(.largeTitle.bold())
            Text("Play cloud games with a mouse and keyboard — the mouse is captured like on a PC.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Spacer()
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: 320)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}
```

```swift
// Apps/PointerLocker/Onboarding/ServiceChooserStep.swift
import SwiftUI

struct ServiceChooserStep: View {
    let services: [ServiceProfile]
    let onChoose: (ServiceProfile) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose your service")
                    .font(.largeTitle.bold())
                    .padding(.top, 48)
                Text("You can change this later in Settings.")
                    .foregroundStyle(.secondary)
                ForEach(services, id: \.id) { service in
                    Button { onChoose(service) } label: { ServiceCard(service: service) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Continues to setup for \(service.name)")
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ServiceCard: View {
    let service: ServiceProfile

    var body: some View {
        HStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color(service.artwork.colors.top), Color(service.artwork.colors.bottom)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 88, height: 88)
                .overlay(Image(systemName: service.artwork.symbol).font(.system(size: 36)).foregroundStyle(.white))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(service.name).font(.title2.bold())
                Text(service.tagline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(20)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 3: Write Get ready**

```swift
// Apps/PointerLocker/Onboarding/GetReadyStep.swift
import SwiftUI

struct GetReadyStep: View {
    let profile: ServiceProfile
    let monitor: ReadinessMonitor
    let onStart: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Get ready for \(profile.name)")
                    .font(.largeTitle.bold())
                    .padding(.top, 48)

                StatusRow(symbol: "computermouse", title: mouseTitle, detail: mouseDetail, ok: monitor.mouse != .notConnected,
                          pulsing: monitor.mouse == .moving && !reduceMotion)
                    .accessibilityLabel("Mouse: \(mouseAccessibility)")
                StatusRow(symbol: "keyboard", title: keyboardTitle, detail: keyboardDetail, ok: monitor.keyboard == .connected)
                    .accessibilityLabel("Keyboard: \(keyboardTitle)")
                StatusRow(symbol: "rectangle.inset.filled", title: displayTitle, detail: displayDetail, ok: monitor.display == .fullScreen)
                    .accessibilityLabel("Display: \(displayTitle). \(displayDetail)")

                ForEach(profile.setupTips) { tip in
                    InfoRow(symbol: tip.symbol, title: tip.title, detail: tip.detail)
                }
                InfoRow(symbol: "escape", title: "Releasing the mouse",
                        detail: "Press ⌘ + . or tap with three fingers. ⌘ + Delete sends Esc to the game.")
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onStart) { Text("Start playing").frame(maxWidth: 320) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.9))
        }
    }

    private var mouseTitle: String {
        switch monitor.mouse {
        case .notConnected: "Connect a mouse or trackpad"
        case .connected: "Mouse connected — move it to test"
        case .moving: "Mouse working"
        }
    }
    private var mouseDetail: String {
        monitor.mouse == .notConnected
            ? "Games need a mouse or trackpad to look around. Touch alone won't work."
            : "The dot lights up when the mouse moves, the same way games receive it."
    }
    private var mouseAccessibility: String {
        switch monitor.mouse {
        case .notConnected: "not connected"
        case .connected: "connected"
        case .moving: "connected and working"
        }
    }
    private var keyboardTitle: String { monitor.keyboard == .connected ? "Keyboard connected" : "Press any key to check the keyboard" }
    private var keyboardDetail: String {
        monitor.keyboard == .connected ? "Ready for WASD." : "Some keyboards only show up after a key press."
    }
    private var displayTitle: String { monitor.display == .fullScreen ? "Full screen" : "The app is in a window" }
    private var displayDetail: String {
        monitor.display == .fullScreen
            ? "Needed to capture the mouse."
            : "Maximize the window, or turn on Full Screen Apps in Settings ▸ Multitasking & Gestures. The mouse can only be captured in full screen."
    }
}

private struct StatusRow: View {
    let symbol: String
    let title: String
    let detail: String
    let ok: Bool
    var pulsing = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).frame(width: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .yellow)
                .font(.title2)
                .scaleEffect(pulsing ? 1.25 : 1)
                .animation(.easeOut(duration: 0.15), value: pulsing)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct InfoRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).frame(width: 36).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 4: Write the hosting controller**

```swift
// Apps/PointerLocker/Onboarding/OnboardingHostingController.swift
import SwiftUI

/// Hosts OnboardingFlow, runs the readiness checks while visible, and tells
/// them the window and screen size (for the full-screen row).
final class OnboardingHostingController: UIHostingController<OnboardingFlow> {
    private let monitor: ReadinessMonitor

    init(start: OnboardingFlow.Start, onFinish: @escaping (ServiceProfile) -> Void, onCancel: (() -> Void)?) {
        let monitor = ReadinessMonitor()
        self.monitor = monitor
        super.init(rootView: OnboardingFlow(start: start, monitor: monitor, onFinish: onFinish, onCancel: onCancel))
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        monitor.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        monitor.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let window = view.window else { return }
        monitor.update(windowSize: window.bounds.size, screenSize: window.screen.bounds.size)
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodegen -q && xcodebuild build -project PointerLocker.xcodeproj -scheme PointerLocker -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Apps/PointerLocker/Onboarding
git commit -m "Onboarding screens: Welcome, Choose your service, Get ready

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Root coordinator — first launch, straight-in launches, switching

**Files:**
- Create: `Apps/PointerLocker/RootViewController.swift`
- Create: `Apps/PointerLocker/ServiceSwitch.swift`
- Modify: `Apps/PointerLocker/AppDelegate.swift:21-24`
- Modify: `Apps/PointerLocker/BrowserViewController.swift` (add `tearDown()`, `sessionPhase(_:)`)
- Modify: `Apps/PointerLocker/BackgroundSessionKeeper.swift` (make `streamPhase` internal as `currentPhase`)
- Test: `Tests/PointerLockerTests/ServiceSwitchTests.swift`

**Interfaces:**
- Consumes: `LaunchRoute`, `OnboardingCompletion` (Task 2), `OnboardingHostingController` (Task 5).
- Produces: `final class RootViewController: UIViewController` with `func showOnboarding(start: OnboardingFlow.Start, cancellable: Bool)`, `func switchService()`, `func showSetupGuide()`; `enum ServiceSwitch { static func needsRebuild(current: ServiceProfile.ID?, chosen: ServiceProfile.ID) -> Bool }`; `BrowserViewController.tearDown()`, `BrowserViewController.sessionPhase(_ completion: @escaping (BackgroundSessionKeeper.StreamPhase) -> Void)`; `BackgroundSessionKeeper.currentPhase(_:)`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PointerLockerTests/ServiceSwitchTests.swift
import XCTest
@testable import PointerLocker

final class ServiceSwitchTests: XCTestCase {
    func testChoosingTheActiveServiceKeepsTheGameRunning() {
        XCTAssertFalse(ServiceSwitch.needsRebuild(current: "geforcenow", chosen: "geforcenow"))
    }

    func testChoosingAnotherServiceRebuilds() {
        XCTAssertTrue(ServiceSwitch.needsRebuild(current: "geforcenow", chosen: "xbox"))
        XCTAssertTrue(ServiceSwitch.needsRebuild(current: nil, chosen: "geforcenow"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command with `-only-testing:PointerLockerTests/ServiceSwitchTests`.
Expected: build error — `cannot find 'ServiceSwitch' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Apps/PointerLocker/ServiceSwitch.swift
import Foundation

enum ServiceSwitch {
    /// Picking the service that's already open just goes back to it; a
    /// different one needs a fresh browser (its identity is fixed at creation).
    static func needsRebuild(current: ServiceProfile.ID?, chosen: ServiceProfile.ID) -> Bool {
        current != chosen
    }
}
```

In `BackgroundSessionKeeper.swift`, rename `private func streamPhase(_:)` to `func currentPhase(_ completion: @escaping (StreamPhase) -> Void)` and update its three callers.

In `BrowserViewController.swift` add (after `applySettingsAndReload()`):

```swift
    /// Which phase the page's session is in (none / queued-loading / playing).
    func sessionPhase(_ completion: @escaping (BackgroundSessionKeeper.StreamPhase) -> Void) {
        sessionKeeper.currentPhase(completion)
    }

    /// Before being replaced (service switch): stop listening to the mouse
    /// and feeding the overlay, and release the lock.
    func tearDown() {
        forceUnlock()
        bridge.invalidate()
        hudFeeder.stop()
        sessionKeeper.willEnterForeground() // stops any keep-alive
    }
```

```swift
// Apps/PointerLocker/RootViewController.swift
import UIKit

/// The window's root: onboarding until a service is chosen, then the browser
/// for it. iPadOS asks the root for pointer lock (and the home indicator,
/// status bar and edge gestures), so those are forwarded to the browser.
final class RootViewController: UIViewController {
    private(set) var browser: BrowserViewController?
    private var onboarding: OnboardingHostingController?

    override var childViewControllerForPointerLock: UIViewController? { browser }
    override var childForHomeIndicatorAutoHidden: UIViewController? { browser }
    override var childForStatusBarHidden: UIViewController? { browser ?? onboarding }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { browser }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch LaunchRoute.resolve(serviceID: Settings.serviceID) {
        case .onboarding: showOnboarding(start: .welcome, cancellable: false)
        case .browser: showBrowser()
        }
    }

    // MARK: Children

    private func embed(_ child: UIViewController) {
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMoveToParent(self)
    }

    private func remove(_ child: UIViewController?) {
        guard let child else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }

    private func showBrowser() {
        browser?.tearDown()
        remove(browser)
        remove(onboarding)
        onboarding = nil
        let browser = BrowserViewController()
        browser.root = self
        self.browser = browser
        embed(browser)
        refreshSystemPreferences()
    }

    private func refreshSystemPreferences() {
        setNeedsUpdateOfPrefersPointerLocked()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    // MARK: Onboarding

    /// First launch embeds onboarding; from Settings it's presented over the
    /// browser and can be cancelled.
    func showOnboarding(start: OnboardingFlow.Start, cancellable: Bool) {
        let controller = OnboardingHostingController(
            start: start,
            onFinish: { [weak self] profile in self?.finishOnboarding(with: profile) },
            onCancel: cancellable ? { [weak self] in self?.dismiss(animated: true) } : nil
        )
        if browser == nil {
            onboarding = controller
            embed(controller)
        } else {
            controller.modalPresentationStyle = .fullScreen
            present(controller, animated: true)
        }
    }

    private func finishOnboarding(with profile: ServiceProfile) {
        let rebuild = browser == nil || ServiceSwitch.needsRebuild(current: Settings.serviceID, chosen: profile.id)
        OnboardingCompletion.finish(with: profile)
        let proceed = { [weak self] in if rebuild { self?.showBrowser() } }
        if presentedViewController != nil { dismiss(animated: true, completion: proceed) } else { proceed() }
    }

    // MARK: From Settings

    /// Settings ▸ Switch service…: warns if a game is running, then the chooser.
    func switchService() {
        guard let browser else { return showOnboarding(start: .chooser, cancellable: true) }
        browser.sessionPhase { [weak self] phase in
            guard let self else { return }
            guard phase != .none else { return self.showOnboarding(start: .chooser, cancellable: true) }
            let alert = UIAlertController(title: "Switch service?",
                                          message: "Switching ends your current game session.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Switch", style: .destructive) { _ in
                self.showOnboarding(start: .chooser, cancellable: true)
            })
            self.present(alert, animated: true)
        }
    }

    /// Settings ▸ Show setup guide: Get ready for the current service.
    func showSetupGuide() {
        showOnboarding(start: .getReady(ServiceProfile.current), cancellable: true)
    }
}
```

In `BrowserViewController.swift` add a weak back-reference used by the Settings sheet (Task 7):

```swift
    /// Set by RootViewController; Settings uses it to switch services.
    weak var root: RootViewController?
```

Because `BrowserViewController` is no longer the root, its `setNeedsUpdateOfPrefersPointerLocked()` / `setNeedsUpdateOfScreenEdgesDeferringSystemGestures()` calls in `setPageLock` must reach the root. Replace those two lines in `setPageLock` with:

```swift
        let host = parent ?? self // the root asks this controller via childViewControllerForPointerLock
        host.setNeedsUpdateOfPrefersPointerLocked()
        host.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
```

In `AppDelegate.swift` replace the root and its comment:

```swift
        // Must be the root view controller: UIKit asks the root for
        // prefersPointerLocked, and RootViewController forwards to the browser.
        window.rootViewController = RootViewController()
```

- [ ] **Step 4: Run tests to verify they pass**

Run the full test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Walk through in the simulator**

Build, install and reset the stored service, then launch:

```bash
xcodebuild build -project PointerLocker.xcodeproj -scheme PointerLocker -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build CODE_SIGNING_ALLOWED=NO | grep -E "error:|BUILD"
xcrun simctl boot "iPad Pro 13-inch (M5)" 2>/dev/null
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/PointerLocker.app
xcrun simctl spawn booted defaults delete sk.icebear.pointerlocker serviceID 2>/dev/null
xcrun simctl launch booted sk.icebear.pointerlocker
```

Check with screenshots (simulator control tool): Welcome → Continue → the GeForce NOW card → Get ready (Mouse "Connect a mouse or trackpad" in the simulator, Full screen ✓) → Start playing → the GeForce NOW page. Relaunch (`xcrun simctl terminate booted sk.icebear.pointerlocker; xcrun simctl launch booted sk.icebear.pointerlocker`): the page opens directly.

Review Focus 1 — pointer lock through the root: start `python3 tools/debug-bridge.py` in the background, enable the overlay (`xcrun simctl spawn booted defaults write sk.icebear.pointerlocker debugHUD -bool true`, relaunch), then run:

```bash
curl -s -m 60 --data-binary 'const d=document.createElement("div");document.body.appendChild(d);await d.requestPointerLock();await new Promise(r=>setTimeout(r,1500));const l=document.getElementById("pointerlocker-hud").textContent.split("\n")[0];document.exitPointerLock();d.remove();return l' localhost:8766/eval
```

Expected: `"lock   page ●  system ●  mice 0"` — `system ●` proves UIKit asked the root and the root forwarded to the browser.

- [ ] **Step 6: Commit**

```bash
git add Apps/PointerLocker Tests/PointerLockerTests/ServiceSwitchTests.swift
git commit -m "RootViewController: onboarding on first launch, straight in afterwards

The root shows onboarding until a service is chosen, then the browser,
and forwards pointer lock, home indicator, status bar and edge gestures to
it. Switching to a different service rebuilds the browser; the same one
just goes back.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Settings sheet and the slimmer ⋯ menu

**Files:**
- Create: `Apps/PointerLocker/SettingsView.swift`
- Modify: `Apps/PointerLocker/BrowserViewController+Menu.swift` (`menuItems()`)
- Modify: `Apps/PointerLocker/BrowserViewController.swift` (present settings, apply on close)

**Interfaces:**
- Consumes: `RootViewController.switchService()`, `.showSetupGuide()` (Task 6); `Settings.*`; `ServiceProfile.current`.
- Produces: `struct SettingsView: View` with `init(service: ServiceProfile, onSwitchService: @escaping () -> Void, onShowSetupGuide: @escaping () -> Void, onClose: @escaping () -> Void)`; `BrowserViewController.showSettings()`.

- [ ] **Step 1: Write the view**

```swift
// Apps/PointerLocker/SettingsView.swift
import SwiftUI

/// ⋯ ▸ Settings…. Values are written to Settings as they change; the
/// browser applies them when the sheet closes (onClose), reloading the page
/// only if the browser identity or debug overlay changed.
struct SettingsView: View {
    let service: ServiceProfile
    let onSwitchService: () -> Void
    let onShowSetupGuide: () -> Void
    let onClose: () -> Void

    @State private var sensitivity = Settings.sensitivity
    @State private var invertY = Settings.invertY
    @State private var keepAlive = Settings.backgroundKeepAlive
    @State private var microphone = Settings.microphone
    @State private var useIdentity = Settings.useServiceIdentity
    @State private var debugHUD = Settings.debugHUD

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    LabeledContent("Playing on", value: service.name)
                    Button("Switch service…", action: onSwitchService)
                    Button("Show setup guide", action: onShowSetupGuide)
                }
                Section("Mouse") {
                    Picker("Sensitivity", selection: $sensitivity) {
                        ForEach(Settings.sensitivityPresets, id: \.self) { Text(String(format: "%g×", $0)).tag($0) }
                    }
                    Toggle("Invert vertical", isOn: $invertY)
                }
                Section {
                    Picker("Keep game running in background", selection: $keepAlive) {
                        ForEach(Settings.backgroundKeepAlivePresets, id: \.seconds) { Text($0.title).tag($0.seconds) }
                    }
                    Picker("Microphone", selection: $microphone) {
                        ForEach(MicrophoneAccess.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Game session")
                } footer: {
                    Text("Keeping the game running lets you switch apps briefly without losing your session.")
                }
                Section {
                    Toggle("Use \(service.name) browser identity", isOn: $useIdentity)
                        .disabled(service.identity == .webKitDefault)
                    Toggle("Debug overlay", isOn: $debugHUD)
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Changes here reload the page.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) } }
        }
        .onChange(of: sensitivity) { Settings.sensitivity = sensitivity }
        .onChange(of: invertY) { Settings.invertY = invertY }
        .onChange(of: keepAlive) { Settings.backgroundKeepAlive = keepAlive }
        .onChange(of: microphone) { Settings.microphone = microphone }
        .onChange(of: useIdentity) { Settings.useServiceIdentity = useIdentity }
        .onChange(of: debugHUD) { Settings.debugHUD = debugHUD }
        .preferredColorScheme(.dark)
    }
}
```

`MicrophoneAccess` must be `Hashable` (it is an enum with a raw value — already `Hashable`).

- [ ] **Step 2: Present it from the browser and apply on close**

In `BrowserViewController.swift` add `import SwiftUI`. Inside the class body (stored properties can't live in extensions) add:

```swift
    /// Browser identity and overlay settings when the Settings sheet opened;
    /// nil while it's closed.
    private var settingsBefore: (identity: Bool, hud: Bool)?
```

and these methods:

```swift
    /// ⋯ ▸ Settings…
    func showSettings() {
        settingsBefore = (identity: Settings.useServiceIdentity, hud: Settings.debugHUD)
        let view = SettingsView(
            service: .current,
            onSwitchService: { [weak self] in self?.closeSettings { self?.root?.switchService() } },
            onShowSetupGuide: { [weak self] in self?.closeSettings { self?.root?.showSetupGuide() } },
            onClose: { [weak self] in self?.closeSettings() }
        )
        let controller = UIHostingController(rootView: view)
        controller.modalPresentationStyle = .formSheet
        controller.presentationController?.delegate = self
        forceUnlock()
        present(controller, animated: true)
    }

    /// Every way out of Settings applies the changes, then continues.
    private func closeSettings(then next: (() -> Void)? = nil) {
        dismiss(animated: true) { [weak self] in
            self?.applySettingsIfOpen()
            next?()
        }
    }

    /// Sensitivity and inversion apply directly; identity and overlay changes
    /// need a reload.
    private func applySettingsIfOpen() {
        guard let before = settingsBefore else { return }
        settingsBefore = nil
        bridge.sensitivity = Float(Settings.sensitivity)
        bridge.invertY = Settings.invertY
        if before.identity != Settings.useServiceIdentity || before.hud != Settings.debugHUD {
            applySettingsAndReload()
        }
    }
```

Handle swipe-to-dismiss the same way:

```swift
extension BrowserViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        applySettingsIfOpen()
    }
}
```

- [ ] **Step 3: Slim the ⋯ menu**

Replace `menuItems()` in `BrowserViewController+Menu.swift` with:

```swift
    private func menuItems() -> [UIMenuElement] {
        let navigation = UIMenu(options: .displayInline, children: [
            UIAction(title: "Back", image: UIImage(systemName: "chevron.backward"),
                     attributes: webView.canGoBack ? [] : .disabled) { [weak self] _ in self?.webView.goBack() },
            UIAction(title: "Reload", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in self?.webView.reload() },
            UIAction(title: "Home", image: UIImage(systemName: "house")) { [weak self] _ in
                self?.webView.load(URLRequest(url: Settings.homeURL))
            },
            UIAction(title: "Open URL…", image: UIImage(systemName: "link")) { [weak self] _ in self?.promptForURL() },
        ])
        let settings = UIAction(title: "Settings…", image: UIImage(systemName: "gearshape")) { [weak self] _ in
            self?.showSettings()
        }
        return [navigation, settings]
    }
```

- [ ] **Step 4: Build and run tests**

Run the full test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Walk through in the simulator**

Install and launch as in Task 6 Step 5 (with `serviceID` set to `geforcenow`). With screenshots:
1. ⋯ shows Back, Reload, Home, Open URL…, Settings….
2. Settings… opens the sheet; change Sensitivity to 1.5× and Done → no reload (page URL unchanged).
3. Toggle Debug overlay on and Done → the page reloads and the overlay appears.
4. Show setup guide → Get ready full screen with Cancel → Cancel returns to the page, same URL.
5. Review Focus 2 — the game keeps its mouse after the guide: after step 4, run the Task 6 Step 5 `curl` lock check again. Expected: `lock   page ●  system ●`, and `raw` in the overlay is unchanged (the simulator has no GCMouse; the live check is on the iPad in Task 8).
6. Switch service… → chooser with Cancel → tap GeForce NOW → Get ready → Start playing → back on the same page without a reload (Review Focus 4).

- [ ] **Step 6: Commit**

```bash
git add Apps/PointerLocker
git commit -m "Settings sheet; the ⋯ menu keeps quick actions only

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Copy pass, accessibility, README, iPad check

**Files:**
- Modify: copy strings in `Apps/PointerLocker/Onboarding/*.swift`, `Apps/PointerLocker/SettingsView.swift`, `Apps/PointerLocker/Services/GeForceNowProfile.swift` (tips)
- Modify: `README.md` ("Build and run" first-run steps; ⋯ menu paragraph)

- [ ] **Step 1: Copy review**

Invoke the `writing-for-interfaces` skill on every user-facing string added in Tasks 1, 5, 6 and 7 (list them with file:line). Apply its fixes. Rebuild and run the full test command; update `testGeForceNowTellsYouToUse1080p` if the tip title changes.

- [ ] **Step 2: Largest text size (Review Focus 5)**

```bash
xcrun simctl spawn booted defaults delete sk.icebear.pointerlocker serviceID
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
xcrun simctl launch booted sk.icebear.pointerlocker
```

Walk to Get ready; screenshot: text wraps, the page scrolls, Start playing stays visible at the bottom. Then `xcrun simctl ui booted content_size large`.

- [ ] **Step 3: VoiceOver labels**

With the debug bridge unavailable to SwiftUI, check via the simulator's Accessibility Inspector (Xcode ▸ Open Developer Tool ▸ Accessibility Inspector, target the simulator): each Get ready status row reads as one element, e.g. "Mouse: not connected", "Display: Full screen. Needed to capture the mouse."

- [ ] **Step 4: README**

In "Build and run", replace step 3's first sentence with: "On first launch, choose your service and follow the Get ready checklist (mouse, keyboard, full screen, and service tips)." Replace the ⋯ button paragraph with: "The **⋯ button** in the bottom-left corner has Back, Reload, Home, Open URL and **Settings…**: switch service, show the setup guide again, mouse sensitivity, invert vertical, background keep-alive, microphone, browser identity and the debug overlay."

- [ ] **Step 5: Commit and install on the iPad**

```bash
git add -A
git commit -m "Onboarding copy pass, accessibility checks, README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
xcodebuild -project PointerLocker.xcodeproj -scheme PointerLocker -configuration Release -destination 'id=00008027-000A791C3611002E' -derivedDataPath build -allowProvisioningUpdates build | grep -E "error:|BUILD"
xcrun devicectl device install app --device 00008027-000A791C3611002E build/Build/Products/Release-iphoneos/PointerLocker.app
```

Ask the user to check on the iPad: onboarding appears once; the Mouse row turns green and pulses when the mouse moves; the Keyboard row turns green after a key press; after Show setup guide ▸ Cancel, mouse-look in a game still works (Review Focus 2).
