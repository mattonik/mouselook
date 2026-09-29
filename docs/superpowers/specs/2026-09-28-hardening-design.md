# Hardening: native pointer lock fallback and service health checks

Date: 2026-09-28
Status: approved design, awaiting spec review

## Why

Mouselook's weak points are outside its code: a service can change how it
detects browsers (GeForce NOW, Figma), and Apple may ship pointer lock in
WebKit on iPad, which the polyfill would currently override. Today both would
fail silently: the mouse simply stops locking and the user doesn't know why.

This work covers two items from the hardening plan:

- **Item 4.** Use WebKit's own pointer lock when it exists and works, and
  fall back to the polyfill when it doesn't.
- **Item 1.** Per-service health checks that notice when a service stopped
  behaving as expected, tell the user once, and keep a local diagnostics log.

Out of scope (later items): identity freshness tests, replaying services'
detection code in tests, keep-alive without GeForce NOW markup, remote
identity config, release checklist.

## Success criteria

- On iPadOS 26 (no native API) nothing changes for the user.
- If WebKit ships pointer lock that works in a web view, pages use it and
  MouseBridge stays idle; if it's refused or never locks, the polyfill takes
  over within 250 ms without the page noticing a difference.
- When GeForce NOW serves its iPad flow, a game never asks for the lock, or
  Figma scrubs without locking, the user sees one plain toast per problem per
  session, Settings ▸ Advanced shows the failed check, and Copy diagnostics
  produces a report someone can paste into a bug report.
- Checks never change the page, never send data anywhere, and log no page
  content, URL paths or keystrokes.

## Findings that shape the design

- iPadOS 26 WebKit exposes no pointer lock API: in a frame the polyfill
  doesn't reach, `Element.prototype.requestPointerLock`,
  `Document.prototype.exitPointerLock` and `document.pointerLockElement` are
  all undefined. Presence of the API before the polyfill runs therefore means
  WebKit added it.
- Figma decides to skip pointer lock in Safari from the user agent
  (`disablePointerLock: <is Safari>`); the Figma profile already presents as
  Chrome. The Figma check exists to notice if that stops working.

## Part 1: Native pointer lock first, polyfill as fallback

`pointerlock-polyfill.js` checks at document start whether
`Element.prototype.requestPointerLock` already exists.

- **No native API (iPadOS 26):** install as today. Behaviour unchanged.
- **Native API present:** keep references to WebKit's `requestPointerLock`,
  `exitPointerLock` and the `pointerLockElement` getter, and install wrappers:
  - A page's request goes to WebKit first.
  - Native succeeds when `document.pointerLockElement` (native getter) is the
    requested element after `pointerlockchange`, or the native promise
    resolves, within 250 ms.
  - Native fails when its promise rejects, `pointerlockerror` fires, or 250 ms
    pass without a lock. The polyfill then locks that same request itself and
    uses the polyfill path for the rest of the page's life (no retrying
    native on later requests).
  - Events the page gets are the same either way: one `pointerlockchange`,
    `pointerLockElement` returns the locked element, `movementX/Y` on moves.
    A native `pointerlockerror` that led to fallback is not passed to the page.
  - `exitPointerLock` and `pointerLockElement` go to whichever path holds the
    current lock.
- The polyfill posts `{type: "lockMode", mode: "native" | "polyfill"}` with
  each lock. On `native`, the app does not activate MouseBridge (WebKit
  delivers movement). The app still sets `prefersPointerLocked`, since it is
  unknown whether WebKit's lock needs it; this is harmless either way.
- Everything else in the polyfill (fullscreen emulation, held keys, modifier
  flags on events, identity) is unaffected.

## Part 2: Health checks in the page

A `ServiceProfile` gets `healthChecks: [HealthCheck]`. A `HealthCheck` has an
`id` and a JavaScript source that installs observers and reports through the
existing message handler as `{type: "health", check: <id>, result: "ok" |
"problem", code: <short string>}`. Checks run after the polyfill in the main
frame, only observe (no DOM changes, no preventDefault), and each reports at
most once per page load. Once a check has reported `ok` on a page it doesn't
report `problem` later on that page.

Checks:

| Check | Service | Problem | OK |
|---|---|---|---|
| `desktop-client` | GeForce NOW | The iPad/touch flow is on screen: the "Add to Home Screen" instructions or the "partially supported browser" notice | A session starts (session phase 1 or 2) |
| `lock-on-click` | GeForce NOW (opt-in per profile) | While the session phase is 2 (streaming), two clicks in a row on the video element are each not followed by a lock request within 2 s | Any lock request while streaming |
| `scrub-lock` | Figma | Press on a scrub control (element inside a `scrubbable` control), drag more than 3 px, and no lock request within 500 ms | A scrub that requests a lock |

A "lock request" is any call to `requestPointerLock`, whichever path handles
it. `desktop-client` matches English text, so if NVIDIA rewords it or shows
another language the check goes quiet: it reports OK only on positive
evidence (a session starting), never merely because the text is absent.
`lock-on-click` is opt-in per profile: on an arbitrary page (controller-only
games, plain video) a click that doesn't lock is normal. (Both revised after
on-device testing and review, 2026-09-29.)

Reports carry only the check id, result, code, service id and page host.

## Part 3: What the app does with results

**HealthMonitor** (new, one per BrowserViewController)

- Receives `health` and `lockMode` messages.
- Keeps the latest result per check id.
- On the first `problem` for a check in a session, shows a toast. A session
  runs from opening a service until switching service or relaunching. A
  toast never repeats within a session.
- While the pointer is locked, a pending toast waits until the lock is
  released.
- Toast text:
  - `desktop-client`: "GeForce NOW didn't load its desktop version, so the
    mouse may not lock. Updating Mouselook usually fixes this."
  - `lock-on-click`: "The game didn't ask for the mouse. Click into the game
    again, or check Settings ▸ Advanced."
  - `scrub-lock`: "Figma didn't lock the pointer while you dragged, so values
    stop at the screen edge."

**DiagnosticsLog** (new)

- Ring buffer of the last 200 timestamped entries, saved on the device
  (Application Support, JSON) so it survives relaunches.
- Entries: check results, the lock path used on each lock, service switches,
  page load failures (existing LoadFailure).
- Same privacy rule: host names only.

**Settings ▸ Advanced**

- "Service checks" row: each check for the current service with ✓ / ⚠︎ /
  "not run yet" and the time of its last result.
- "Copy diagnostics": copies a plain-text report to the clipboard with the
  app version and build, iPadOS and WebKit versions, current service, the
  browser identity it presents, the lock path, check results, and the log.

## Error handling

- A check script that throws is caught inside the page and reports nothing;
  a broken check never breaks the page or the lock.
- Unknown check ids or malformed messages are ignored by HealthMonitor.
- If the log file can't be read, the log starts empty; if it can't be
  written, entries stay in memory for the session.

## Testing

- **Playwright (polyfill):**
  - No native API: polyfill path, as today.
  - Native API present and working (Chromium's): the page gets a native lock,
    `lockMode` reports `native`, one `pointerlockchange`.
  - Native refused (stubbed to reject): the polyfill takes over within 250 ms,
    `lockMode` reports `polyfill`, no `pointerlockerror` reaches the page.
- **Playwright (checks):** each check against a fixture page for its problem
  scenario and its healthy scenario, including "reports at most once" and "ok
  wins".
- **Swift:** HealthMonitor (toast once per check per session, deferred while
  locked, reset on service switch); DiagnosticsLog (cap of 200, survives a
  reload from disk, empty on unreadable file); diagnostics text (sections
  present, no URL paths).
- **On device:** GeForce NOW and Figma normally show all checks ✓. To see a
  problem, temporarily switch the Figma profile to the Mac Safari identity:
  scrubbing shows the `scrub-lock` toast once and ⚠︎ in Settings.

## Risks

- `lock-on-click` could fire in games that deliberately don't lock (point and
  click games). Two misses in a row and the "ok wins" rule limit this; if it's
  still noisy, restrict it to games that have locked before.
- Figma's `scrubbable` class names come from its build; if they change, the
  check goes quiet rather than raising false alarms.
- A future WebKit might support pointer lock in a way we can't foresee (for
  example requiring a permission prompt). The 250 ms fallback keeps mouse-look
  working, and the log records which path was used.
