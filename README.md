# PointerLocker

An iPad browser, built on the system WKWebView, that gives web pages a working
**Pointer Lock API**. The target is GeForce NOW's web client
(`play.geforcenow.com`), which needs pointer lock for mouse-look in games.
Safari and WebKit on iPadOS don't implement pointer lock.

The app is for personal use. You sideload it with Xcode.

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

It also reports `navigator.maxTouchPoints = 0` and uses a Mac Safari user
agent. Without that, GeForce NOW detects the iPad and serves its touch/PWA
client, which never requests pointer lock. You can turn this off in the menu.

### Ways to release the lock

- **Hold Esc for 1 second**, the same gesture GeForce NOW uses. A short tap on
  Esc still reaches the game.
- **Three-finger tap** on the screen. This is for keyboards without an Esc key,
  such as the Magic Keyboard. You can also remap Caps Lock to Escape under
  Settings ▸ General ▸ Keyboard ▸ Hardware Keyboard ▸ Modifier Keys.
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

1. For each target, go to **Signing & Capabilities**. Pick your team and change
   the bundle identifier to something unique, such as `sk.yourname.pointerlocker`.
2. Choose the **PointerLocker** scheme and your iPad, then Run. With a free
   Apple ID the app must be re-signed every 7 days.
3. Pair a mouse or trackpad and a keyboard. Run the app **full screen**: iPadOS
   grants pointer lock only to a full-screen, frontmost app. If the cursor stays
   visible, a toast explains why.

The **⋯ button** in the bottom-left corner has Back, Reload, Home, Open URL,
mouse sensitivity, invert vertical, and the "Pretend to be a Mac" toggle. It
hides while the pointer is locked.

The **MouseLockPrototype** scheme is milestone 1 from the brief. It's a bare
GCMouse delta viewer. Run it first to confirm that your mouse gives smooth,
unbounded deltas. Also check the **sign of dY** when you move the mouse up.
PointerLocker assumes up is positive, as GameController reports it. If vertical
look comes out inverted, toggle *Invert vertical*.

### Debugging

`isInspectable` is on. On a Mac, open Safari ▸ Develop ▸ *your iPad* ▸
PointerLocker to get the Web Inspector for the page. There you can check
`window.__pointerLocker.isLocked` and watch events arrive.

### Tests

The polyfill is tested in headless Chromium by driving the same batch protocol
the native side uses:

```sh
npm install && npm test
```

CI (`.github/workflows/build.yml`) runs those tests. It also builds both iOS
targets for the Simulator on a macOS runner.

## Known risks and what to try

- **`event.isTrusted`.** Synthetic events have `isTrusted === false`. If GeForce
  NOW filters on it, mouse-look won't work even though the lock succeeds. You
  can check in Web Inspector whether the stream reacts to
  `__pointerLocker.batch([["m",50,0]])`. If it doesn't, the fallback is the
  WebKit-fork plan in [`docs/webkit-fork-plan.md`](docs/webkit-fork-plan.md),
  which produces trusted events.
- **Browser detection.** GeForce NOW may still redirect or block. You can try
  toggling the Mac spoofing, or a Chrome user agent in `Settings.swift`.
- **Scroll wheel scale.** `MouseBridge.wheelScale` is a first guess and may need
  tuning.
- **Keyboard focus.** Keys go to the web view through the normal responder
  chain. If keys stop working after a lock, tap the page once before locking.
