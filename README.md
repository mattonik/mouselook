# Mouselook

An iPad browser, built on the system WKWebView, that gives web pages a working
**Pointer Lock API**, so a mouse works the way it does on a computer. Safari and
WebKit on iPadOS don't implement pointer lock. Two kinds of service use it:

- **Play:** cloud games such as GeForce NOW (`play.geforcenow.com`), for
  mouse-look: aiming and looking around.
- **Create:** design tools such as Figma, for dragging number fields and
  panning without the pointer stopping at the screen edge.

**Website:** [icebear.digital/mouselook](https://icebear.digital/mouselook).
The app is free to build from this repository, and is coming to the App Store
as a $9.99 one-time purchase. To join the TestFlight beta, see the website.

You can sideload it with Xcode; to build it under your own Apple ID, change
`DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`. The bundle
ID is `sk.icebear.mouselook`; the Xcode project and target are still called
PointerLocker. Copies installed before the bundle ID change are a separate app
with their own settings and sign-ins.

## Approach

The [original plan](docs/webkit-fork-plan.md) was to fork WebKit and enable
its dormant pointer-lock code for iOS. That is months of work: builds that take
hours, IPC plumbing, and losing JIT. This repo takes a shorter path that
needs no WebKit changes. It connects three stock iPadOS APIs:

| Layer | How |
|---|---|
| Hide and freeze the system cursor | `UIViewController.prefersPointerLocked` (iPadOS 14+, the API native games use) |
| Raw, unbounded mouse deltas and buttons | `GCMouse` from GameController, which is what `MouseLockPrototype` validates |
| Pointer Lock API for the page | [`pointerlock-polyfill.js`](Apps/PointerLocker/Resources/pointerlock-polyfill.js), injected at document start |

```
 page: canvas.requestPointerLock()
   └─► polyfill ──postMessage("lock")──► BrowserViewController
                                           ├─ prefersPointerLocked = true  (cursor hidden)
                                           └─ MouseBridge.isActive = true
 GCMouse deltas/buttons/scroll ─► MouseBridge ─(1 batch per display frame)─►
   evaluateJavaScript("__pointerLocker.batch([...])")
   └─► polyfill dispatches pointermove/mousemove (movementX/Y),
       pointerdown/mousedown/…/click, contextmenu, wheel on the locked element
```

What the polyfill provides:

- `Element.requestPointerLock()`, which returns a Promise and accepts
  options.
- `document.exitPointerLock()` and `document.pointerLockElement`.
- `pointerlockchange` and `pointerlockerror`, including the
  `document.onpointerlockchange = …` form.
- `movementX` and `movementY` on events, and `getCoalescedEvents()`.
- Correct `buttons` bitmask and chording.
- Real mouse events are swallowed while the lock is on, so clicks aren't
  delivered twice.
- The lock is released when the locked element is removed from the document.
- The Fullscreen API is emulated in the page: the element is pinned over the
  viewport. The app is already full screen, and native element fullscreen
  would move the web view out of the app's view controller. Pointer lock would
  then stop working, and the web view comes back at 0×0, so the stream goes
  black.
- Web Workers also see the Mac `navigator.platform`. GeForce NOW checks it
  there, so they need it too.

It also reports `navigator.maxTouchPoints = 0` and uses a Mac Safari 26.4 user
agent. From 26.4 on, GeForce NOW treats Safari as fully supported: it skips
the "partially supported on Safari" dialog and passes Esc straight to the
game. Without that, GeForce NOW detects the iPad and serves its touch/PWA
client, which never requests pointer lock. You can turn this off in the menu.

### Ways to release the lock

- **Hold Esc for 1 second**, the same gesture GeForce NOW uses. A short tap on
  Esc still reaches the game.
- **⌘ + .** (Command-period), for keyboards without an Esc key, such as the
  2020–2022 Magic Keyboard or the Smart Keyboard Folio. The app handles it, so
  the game never receives it.
- **Three-finger tap** on the screen.

On a keyboard without Esc, use **⌘ + Delete** to send Esc to the game (for
menus). GeForce NOW maps that combination on Safari. You can also remap Caps
Lock to Escape under Settings ▸ General ▸ Keyboard ▸ Hardware Keyboard ▸
Modifier Keys.
- The lock is released automatically when you switch apps, the page
  navigates, or the system drops the pointer lock (for example, when you enter
  Stage Manager).

## Build and run

You need a Mac with Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen                      # generates PointerLocker.xcodeproj
open PointerLocker.xcodeproj
```

1. `project.yml` signs with the IceBear s.r.o. team and `sk.icebear.*` bundle
   IDs. To build with another account, change `DEVELOPMENT_TEAM` and the bundle
   IDs there (or under **Signing & Capabilities** in Xcode) to your own.
2. Choose the **PointerLocker** scheme and your iPad, then Run. With a free
   Apple ID the app must be re-signed every 7 days.
3. On first launch, choose your service and follow the Get ready checklist
   (mouse, keyboard, full screen, and service tips). iPadOS grants pointer lock
   only to a full-screen, frontmost app. If the cursor stays visible, a toast
   explains why.

The **⋯ button** in the bottom-left corner lists the services first (GeForce
NOW, Figma): pick one to switch straight to it. Each service reopens the page you
were last on, such as the open Figma file; a running game asks before you leave.
Below that are Back, Reload, Home, Open URL and **Settings…**: switch service
(with the setup guide), show the setup guide again, mouse sensitivity, invert
Y-axis, background keep-alive, microphone, browser identity, the debug overlay,
service checks, and About (version, links to the website and this
repository). The button hides while the pointer is locked.

**Switching apps mid-game.** iPadOS suspends an app within seconds of leaving
it, which drops the stream and ends the session. Mouselook keeps itself
running in the background during a session. While you wait in the queue or the
game loads, it keeps running until the game starts, for up to 30 minutes. While
a stream plays, it keeps running for 5 minutes by default (⋯ ▸ Settings… ▸ Keep game
running in background: Off / 1 / 5 / 15 minutes). It does this by playing silence,
since WebKit pauses a quiet stream in the background. When the time is up it
pauses the stream so the system can suspend the app. GeForce NOW still needs a
tap on Resume when you come back.

**Volume won't go to zero?** If you allowed the microphone, WebKit uses the
voice-call audio mode, in which iPadOS keeps a minimum volume. Set ⋯ ▸ Settings… ▸
Microphone ▸ Don't Allow if you don't need voice chat.

**Stream resolution.** On iPad, GeForce NOW defaults to 4:3 sizes such as
1112×834. Some games then fail to find a free server and report "at capacity"
or "not available". Set GeForce NOW ▸ Settings ▸ Gameplay ▸ Streaming quality ▸
Custom ▸ Resolution to 1920×1080. The setting is saved with your account.

**Figma.** Pick Figma in onboarding (or ⋯ ▸ Settings… ▸ Switch service…) to
use its design editor. Dragging a number's label scrubs the value without
stopping at the screen edge, and Space + drag pans the canvas. The Figma profile
presents as Chrome on a Mac, not Safari: Figma turns pointer lock off for
scrubbing in Safari. Sign in with email and password.

The **MouseLockPrototype** scheme is milestone 1 from the brief. It's a bare
GCMouse delta viewer. Run it first to confirm that your mouse gives smooth,
unbounded deltas. Also check the **sign of dY** when you move the mouse up.
Mouselook assumes up is positive, as GameController reports it. If vertical
look comes out inverted, toggle *Invert Y-axis*.

### Debugging

**Service checks.** Mouselook watches for signs that a service changed how it
treats this browser (GeForce NOW loading its iPad version, a game never asking
for the mouse, Figma not locking while you scrub) and says so once per
session. ⋯ ▸ Settings… ▸ Service checks shows the results; Copy diagnostics
puts a report with the app, iPadOS and WebKit versions, the lock path and the
last 200 events on the clipboard. Nothing leaves the iPad unless you paste it
somewhere.

Turn on **Debug overlay** in ⋯ ▸ Settings…. The page reloads, and a small panel in
the bottom right shows:

- **lock**: the page's lock, the system pointer lock, and connected mice
- **mouse**: raw GCMouse events/s against the mousemove events/s the page receives
- **input**: buttons and keys held, and click counts per button, as the page sees them
- **stream**: resolution, fps, codec, bitrate, round-trip time, jitter, loss and dropped frames

If `page ●` shows but `system ○` doesn't, iPadOS refused the pointer lock. On
iPadOS 26 the app can open as a resizable window. Maximize it, because only a
full-screen app gets the lock.

`isInspectable` is on. On a Mac, open Safari ▸ Develop ▸ *your iPad* ▸
Mouselook to get the Web Inspector for the page. There you can check
`window.__pointerLocker.isLocked` and watch events arrive.

In the simulator, Debug builds also run a small remote console
([`DebugBridge.swift`](Apps/PointerLocker/DebugBridge.swift)), so you can script
the page from the Mac's terminal:

```sh
python3 tools/debug-bridge.py &
curl -s --data-binary 'return document.pointerLockElement?.id' localhost:8766/eval
```

### Tests

Run everything CI runs on your Mac before pushing:

```sh
npm install          # once
tools/test.sh        # Swift unit tests on an iPad simulator + polyfill tests
tools/test.sh swift  # or: js; extra arguments go to xcodebuild
```

Builds are incremental (derived data in `build/`), so repeat runs take
seconds. The Swift suite covers mouse batching, the mouse hub, service
profiles and categories, onboarding logic, page recovery and settings; the
polyfill is tested in headless Chromium by driving the same batch protocol
the native side uses.

CI (`.github/workflows/build.yml`) runs on every pull request, on merges to
`main` and on demand, as one Linux job for the polyfill and one macOS job that
builds and tests the app.

## Code layout

| Piece | What it does |
|---|---|
| `Services/ServiceProfile.swift` | What's specific to one streaming service: home page, the browser identity the pages see, and how to tell that a session is running. |
| `Services/GeForceNowProfile.swift` | The GeForce NOW profile and why it looks the way it does. Add another service as another file like this one. |
| `Resources/pointerlock-polyfill.js` | Pointer Lock and Fullscreen APIs in the page. It applies the profile's identity, including inside Web Workers, and turns native input into DOM events. |
| `MouseBridge.swift` | Raw GCMouse input to the page, one batch per frame, never more than one in flight. |
| `BrowserViewController*.swift` | The web view and lock state (+Menu, +WebUI for popups, dialogs and permissions). |
| `BackgroundSessionKeeper.swift`, `BackgroundKeepAlive.swift` | Keeping a session alive across app switches. |
| `PageRecovery.swift`, `StatusOverlayView.swift` | Crashes, failed loads and going offline. |
| `DebugHUDFeeder.swift`, `Resources/debug-hud.js`, `DebugBridge.swift` | The debug overlay, and the Mac-side JavaScript console (Debug builds only). |

### When things go wrong

- **The page process crashes** (for example when memory runs low): the app
  reloads the page. After 3 crashes within a minute it stops and offers a
  Reload button, so it can't get stuck in a loop.
- **A page fails to load**: the app shows why instead of a blank page: "You're
  offline" (it loads the page again once the connection is back), "Can't reach
  <site>" when online but the site doesn't answer, or the system's reason.
- **Stuck input**: releasing the mouse releases any held mouse buttons. So
  does disconnecting the mouse. Keys held when the app loses focus get their
  key-up.
- **The page stalls**: mouse input waits for the page instead of piling up,
  so a hiccup doesn't end in a burst of stale movement.

## Known risks and what to try

- **`event.isTrusted`.** Synthetic events have `isTrusted === false`. Tested
  in the simulator (Sept 2026): GeForce NOW doesn't filter on it. Each
  `__pointerLocker.batch([["m",dx,dy]])` while locked becomes one message on
  its `input_channel_v1` data channel. If that ever changes, the fallback is the
  WebKit-fork plan in [`docs/webkit-fork-plan.md`](docs/webkit-fork-plan.md),
  which produces trusted events.
- **Browser detection.** GeForce NOW may still redirect or block. You can try
  toggling the Mac spoofing, or a Chrome user agent in `Settings.swift`.
- **Scroll wheel scale.** `MouseBridge.wheelScale` is a first guess and may need
  tuning.
- **Keyboard focus.** Keys go to the web view through the normal responder
  chain. If keys stop working after a lock, tap the page once before locking.

## License

The code is licensed under the [Apache License 2.0](LICENSE). The name
"Mouselook" and the app icon are not covered by the license: if you publish
your own build, give it a different name and icon.
