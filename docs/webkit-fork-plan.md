> **Status: Plan B.** The app in this repo uses a lighter approach instead
> (system WKWebView + `prefersPointerLocked` + GCMouse + a JS Pointer Lock
> polyfill; see the top-level README). This fork plan is the fallback if the
> page rejects synthetic (`isTrusted === false`) input events.

# Project brief: Pointer lock for GeForce NOW on iPadOS

## Goal

GeForce NOW has no native iPadOS app; Safari's web client can't do mouse-driven
games because **Safari/WebKit on iOS and iPadOS does not implement the Pointer
Lock API at all, in any version, including iOS/iPadOS 26.** This is a deliberate
WebKit limitation on touch-first platforms, not a bug or fullscreen-specific
restriction.

A commercial app (**CloudGear**, by Bitwise Solutions) already solves this by
building a native streaming client rather than wrapping a browser. This project
explores whether a narrower, open, WebKit-based fix is feasible: getting real
pointer lock working inside WebKit on iPadOS, so any pointer-lock-dependent
site (not just GFN) works natively.

**Scope constraint:** only pointer lock (raw, unbounded mouse deltas + cursor
hiding) is needed — not higher resolution, HDR, or custom video decode. GFN's
own web client already handles video/audio via standard browser media APIs;
the video/audio pipeline is *not* part of this project.

## Why this is more tractable than it sounds

Reverse-engineering NVIDIA's proprietary GFN streaming protocol (what CloudGear
had to do) is out of scope. This project only needs to solve the **input**
side: get raw mouse deltas from iPadOS into WebKit's existing, spec-compliant
Pointer Lock implementation (which already works on macOS Safari).

## Research findings so far

- **WebKit is open source** (github.com/WebKit/WebKit), buildable for iOS via
  `Tools/Scripts/build-webkit --ios-device` (requires macOS + Xcode).
- **Pointer Lock DOM/WebCore layer already exists** and is shared cross-platform
  (`Element.requestPointerLock()`, `pointerlockchange`/`pointerlockerror`
  events, `MouseEvent.movementX/Y`). This is *not* something to rebuild — macOS
  Safari already ships it.
- **`ENABLE(POINTER_LOCK)` guards exist in iOS-tagged code**, but a 2021
  changeset (`r279059`) shows the movement-delta plumbing being reused for
  **Live Text hover recognition**, not exposed as the standard API. So the iOS
  platform layer has *some* delta-handling code, just not wired to pointer
  lock.
- **Active gaming-driven pressure exists at WebKit**, but scoped to macOS: an
  open proposal for "Pointer Lock Unadjusted Movement"
  (`WebKit/standards-positions#254`), explicitly noted as requested by "gaming
  platforms on the web," with a WIP implementation PR
  (`WebKit/WebKit#17525` by Apple engineer James Howard). No open effort found
  targeting iOS enablement specifically.
- **No existing open-source project does this for iOS.** Searched GitHub,
  jailbreak/sideloading communities, WebKit Bugzilla — nothing found. This is
  unclaimed work, not a case of "just find the existing patch."
- **Relevant real source files identified** (via github.com/WebKit/WebKit):
  - `Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm` — where iOS
    touch/gesture input already gets translated into `WebPageProxy` calls
    (e.g. `_page->handleTwoFingerTapAtPoint(...)`). Most likely injection point
    for mouse-lock input.
  - `Source/WebKit/UIProcess/ios/WKContentView.h` / `.mm`
  - `Source/WebKit/UIProcess/WebPageProxy.h` — UI-process/WebContent-process
    IPC interface; confirmed to be a file that legitimately gets edited for
    input-plumbing changes (a Jan 2025 commit modified this file plus
    `PlatformMouseEvent.h` for stylus pointer-type support).
  - macOS equivalent for comparison: `WebViewImpl.mm` (where `NSEvent`
    mouse events already flow into the same cross-platform pointer-lock code).

## Proposed technical layers

1. **Input capture** — `GCMouse.current.mouseInput.mouseMovedHandler` (raw
   deltaX/deltaY, GameController.framework, available since iPadOS 14).
   *Prototype already built — see below.*
2. **Cursor suppression** — avoid/suppress `UIPointerInteraction` on the
   WKWebView content view while locked.
3. **IPC bridging (the core novel work)** — forward captured deltas from the
   UI process into the WebContent process as synthetic `PlatformMouseEvent`s,
   likely reusing/extending the existing touch-event IPC channel in
   `WKContentViewInteraction.mm` / `WebPageProxy.h`.
4. **WebCore/DOM layer** — probably already correct; just needs real iOS input
   feeding it instead of being compiled out.
5. **Build config** — flip `ENABLE_POINTER_LOCK` on for the iOS port target.
6. **Edge cases needing real design work:**
   - Unlock gesture without a hardware Escape key
   - Split View / Stage Manager focus changes while locked
   - Suppressing two-finger-tap (right-click equivalent) while locked

Steps 3 and 6 are the genuinely novel iOS-specific engineering. Steps 1, 2, 4,
5 are largely reusing existing Apple APIs or re-enabling dormant code.

## Current status / what's done

- **Milestone 1 prototype written**: `MouseLockPrototype.swift` — standalone
  SwiftUI app, no WebKit dependency, validates raw GCMouse delta capture in
  isolation. Not yet built or tested on-device.

## Next steps for Claude Code

1. Set up an Xcode project from `MouseLockPrototype.swift`, build for iOS
   Simulator to confirm it compiles (note: GCMouse hardware input requires a
   physical mouse/trackpad on a real iPad — Simulator can validate the build
   but not real hardware deltas).
2. Once validated on-device: clone `github.com/WebKit/WebKit`, get a baseline
   iOS build working (`Tools/Scripts/build-webkit --ios-device`) before any
   modifications — this alone can take hours on first build.
3. Read `WKContentViewInteraction.mm` and `WebPageProxy.h` in full to map the
   exact existing touch-event IPC path, then sketch where a mouse-lock delta
   message would plug in, following the same pattern as existing gesture
   handlers (e.g. `handleTwoFingerTapAtPoint`).
4. Compare against the macOS pointer-lock implementation (`WebViewImpl.mm`
   and related `EventHandler.cpp` usage) to understand what the iOS path needs
   to produce to reach the same cross-platform WebCore entry points.
5. Flip `ENABLE_POINTER_LOCK` on for the iOS port build target and confirm it
   compiles before adding real logic.
6. Iterate: attach the GCMouse capture layer (validated in step 1) to the IPC
   bridge, test `requestPointerLock()` on a real page.

## Known constraints

- Distribution: this cannot ship on the App Store using a custom WebKit build
  (Apple requires system WebKit unless going through the restrictive EU
  BrowserEngineKit program). Sideloading onto your own device via Xcode
  (free Apple ID, 7-day re-sign, or $99/yr developer account for 1-year
  signing) is the realistic distribution path for personal use.
- No JIT entitlement without Apple's sanction — JavaScriptCore runs
  interpreted rather than JIT-compiled in a self-built, non-Apple-signed
  browser. Likely tolerable since GFN's page is WebRTC-session-setup-heavy,
  not compute-heavy.
- This is a personal-use exploration, not a distribution project.
