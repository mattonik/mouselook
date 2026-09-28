# Onboarding and service selection — design

Date: 2026-09-28
Status: approved in conversation, awaiting spec review

## Goal

PointerLocker is heading for a wider audience (eventually public). A first-time
user should be able to pick their streaming service, get their iPad ready, and
start playing without knowing any of the tricks we learned the hard way (full
screen, 1920×1080, how to release the mouse). After that the app opens straight
into the chosen service, and the service can be changed later in Settings.

Success looks like:

- First launch: welcome → choose a service → a "get ready" checklist → the
  service's page, with no dead ends.
- Every later launch goes straight to the chosen service.
- The service can be switched, and the setup guide reopened, from Settings.
- The ⋯ menu shrinks to quick actions; options move to a Settings screen.

## Decisions (from the conversation)

- Audience: wider/public → App Store-grade polish; no official logos or anything
  implying affiliation with NVIDIA, Microsoft, etc.
- Onboarding depth: option B — choose a service, then one "Get ready" page for
  that service. Teaching beyond that (in-context tips, tutorial) belongs to the
  next sub-project ("user communication").
- Switching lives in a new Settings screen (option B); the ⋯ menu keeps quick
  actions only. Revisit after user testing.
- UI: SwiftUI screens hosted in the existing UIKit app (approach 1). The browser
  and pointer-lock code stay UIKit.
- Switching service rebuilds the browser screen with a fresh web view.

## Flow

On launch a root coordinator (UIKit container view controller) decides:

- `Settings.serviceID == nil` (first launch, or the stored ID is unknown) →
  onboarding.
- Otherwise → `BrowserViewController` for `ServiceProfile.current`.

Onboarding is full screen, three steps:

1. **Welcome.** App name, one line: "Play cloud games with a mouse and keyboard
   — the mouse is captured like on a PC." Button: Continue.
2. **Choose your service.** One card per `ServiceProfile.selectable` (only
   GeForce NOW now): artwork, name, tagline. Tapping a card selects it and moves
   on.
3. **Get ready** for the chosen service: a checklist with live status (see
   Readiness), the profile's setup tips, and how to release the mouse.
   Button: Start playing — always enabled; warnings inform, never block.
   Tapping it saves `serviceID` and swaps to the browser.

Nothing is saved before Start playing, so an interrupted onboarding simply
starts again.

## Settings screen

Opened from ⋯ ▸ Settings… as a sheet (SwiftUI `Form`):

- **Service**: current service; "Switch service…" (service chooser as a sheet →
  that service's Get ready → browser rebuilds); "Show setup guide" (Get ready
  for the current service, no switch).
- **Mouse**: sensitivity, invert vertical.
- **Game session**: keep running in background, microphone.
- **Advanced**: use <service> browser identity, debug overlay.

Switching while a session is running (session phase ≠ none, via the profile's
`sessionPhaseScript`) first asks: "Switching ends your current game session."

The ⋯ menu becomes: Back, Reload, Home, Open URL…, Settings….

Settings that need a reload (identity, debug overlay) apply when the sheet
closes, as today's menu items do.

## Service model

`ServiceProfile` gains presentation data; the engine is unchanged.

```swift
struct ServiceProfile {
    // existing: id, name, homeURL, identity, sessionPhaseScript
    let tagline: String            // "NVIDIA's cloud gaming service"
    let artwork: ServiceArtwork    // SF Symbol + two gradient colours; no logos
    let setupTips: [SetupTip]      // service-specific Get ready items
}

struct SetupTip {
    let symbol: String             // SF Symbol name
    let title: String
    let detail: String
}
```

- `ServiceProfile.selectable` lists what onboarding offers (GeForce NOW). The
  `generic` profile stays internal.
- GeForce NOW tip: "Set the stream to 1920×1080" — "In GeForce NOW: Settings ▸
  Gameplay ▸ Streaming quality ▸ Custom ▸ Resolution. Some games won't start at
  the iPad's default size."
- `Settings.serviceID` becomes `String?`; `nil` means not chosen. Existing
  installs have none stored and see onboarding once. `ServiceProfile.current`
  keeps falling back to GeForce NOW so early reads can't crash.
- Home URL stays per service (already). Sensitivity, microphone and keep-alive
  stay global.
- Switching replaces the `BrowserViewController`; the new web view is built from
  the new profile. The default website data store is shared, so sign-ins to
  each service survive switching.

## Readiness (Get ready page)

`ReadinessMonitor` (`@Observable`, main actor) runs only while the page is
visible.

| Check | Source | States |
|---|---|---|
| Mouse | `GCMouse.mice()` + connect/disconnect notifications; GCMouse deltas | not connected / connected / moving (≈0.3 s after deltas) |
| Keyboard | `GCKeyboard.coalesced` + connect/disconnect notifications | not detected ("press any key to check") / connected |
| Full screen | window scene bounds vs screen bounds, on size changes | full screen / in a window (+ how to fix) |

- Movement uses GCMouse deltas — the same path games use, so green means games
  get the mouse too.
- A trackpad that appears as a GCMouse counts as a mouse.
- Full-screen advice covers iPadOS 26 windowing ("maximize the window, or turn
  on Full Screen Apps in Settings ▸ Multitasking & Gestures") and Stage Manager.
- The monitor's inputs (mouse count, keyboard present, window/screen size,
  delta events) are injectable for unit tests.

Static rows below the checks: the profile's `setupTips`, then "Release the
mouse: ⌘ + . or a three-finger tap. ⌘ + Delete sends Esc to the game."

## Presentation

- Dynamic Type; VoiceOver labels on status rows ("Mouse: connected and
  working"); Reduce Motion replaces the movement pulse with a static state.
- Landscape and portrait; works in a window (the case the full-screen row
  explains).
- Dark appearance throughout, matching the game pages.
- Copy reviewed with the writing-for-interfaces skill before shipping.

## Testing

Unit tests (XCTest):

- Coordinator: no service → onboarding; valid → browser; unknown → onboarding.
- `ReadinessMonitor` state transitions from injected inputs.
- Every selectable profile has name, tagline, artwork and valid tips.
- `serviceID` migration (nothing stored → nil).

Simulator: walk through onboarding and Settings ▸ Switch service with
screenshots; check the browser rebuilds with the right profile and sign-ins
persist.

iPad: live mouse/keyboard checks (the simulator has no GCMouse).

## Out of scope

Handled in the "user communication" sub-project: in-context tips (e.g. "Mouse
locked · ⌘. to release" on first lock), reworking error and prompt copy across
the app, a tutorial, and "Reset tips" in Settings. Also not included: a
user-facing "any website" profile, app icon and launch screen.
