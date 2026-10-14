# Background keep-alive (removed in build 5)

Builds 1–4 kept Mouselook running for a while after you switched away from a
game, so a GeForce NOW session survived a quick look at another app. App
Review rejected 1.0 (build 4) under guideline 2.5.4 on 13 October 2026, and
build 5 removed the feature. This note records why it existed, how it worked
and what we learned, in case it comes back in a form App Review accepts.

## Why it was there

iPadOS suspends an app a few seconds after it leaves the screen. For a cloud
game that drops the stream and can end the session; even with the
keep-alive, GeForce NOW needed a tap on Resume on return. The worst case was
losing your place in a queue of up to 30 minutes to answer a message.

## How it worked

Two files, both deleted in build 5:

- `Apps/PointerLocker/BackgroundKeepAlive.swift` played **silence** natively:
  an `AVAudioEngine` with an `AVAudioSourceNode` that filled every buffer with
  zeros and set `isSilence`. The audio session was `.playback` with
  `.mixWithOthers` (or left as `.playAndRecord` when the microphone was in
  use). With `UIBackgroundModes: [audio]` in `project.yml`, iPadOS doesn't
  suspend an app while its audio session plays, even silently. A timer
  stopped it after a set time and released the audio session.
- `Apps/PointerLocker/BackgroundSessionKeeper.swift` decided when. On
  `UIScene.didEnterBackgroundNotification` it read the page's session phase
  through the service profile's `sessionPhaseScript`:
  - **none** (library, sign-in): nothing; the app suspends as usual;
  - **starting** (queued or loading): keep alive until the game starts, up to
    30 minutes, checking the phase every 5 s;
  - **playing**: keep alive for the chosen time, then
    `WKWebView.pauseAllMediaPlayback()` so the system could suspend the app.

  Coming back to the foreground stopped everything.

Setting: ⋯ ▸ Settings… ▸ Game session ▸ "Keep game running in background":
Off / 1 / 5 / 15 minutes, default 5, stored as `backgroundKeepAlive` in
`UserDefaults`. Off paused media on leaving, as build 5 now always does.

### Why silence and not the game's own audio

WebKit treats a quiet stream as silent and pauses it when the app goes to the
background, and the app is then suspended within seconds. So the page's audio
alone didn't keep the app running, and the app had to hold the audio session
itself. That is exactly what 2.5.4 forbids: the reviewer heard nothing in the
background, because by design there was usually nothing to hear, above all
during the queue.

## What testing showed

- Simulator (27 September 2026): 90 s in the background with keep-alive, the
  stream kept playing and the session continued on return. The simulator never
  suspends backgrounded apps, so suspension after the time limit was never
  confirmed there.
- Not measured: how long GeForce NOW holds a session when the app is
  suspended, i.e. what users lose without the keep-alive. Worth testing on a
  device before deciding to bring it back.

## What stays in the app

`StreamPhase` (in `ServiceProfile.swift`) and each profile's
`sessionPhaseScript`: switching services asks first when a game is running,
and the health checks read the phase too.

## If we revisit it

Options that could pass 2.5.4, none tested:

- **Audible content only.** Keep the `audio` mode only while the game's own
  audio is actually audible in the background, and never during the queue.
  Needs a device test of whether WebKit keeps an audible WebRTC stream playing
  in the background, and a Home Screen screen recording for App Review.
- **Picture in Picture** of the stream, if WebKit allows PiP for a MediaStream
  video. Picture in Picture is a legitimate use of the same background mode.
- **Faster recovery instead of staying alive:** make coming back to a dropped
  session quick (reload straight into GeForce NOW's resume flow).

To get the old code back:

```bash
git log --diff-filter=D --format=%h -- Apps/PointerLocker/BackgroundKeepAlive.swift
```

then `git show <hash>^:Apps/PointerLocker/BackgroundKeepAlive.swift` (and the
same for `BackgroundSessionKeeper.swift`, `Settings.swift`, `SettingsView.swift`
and `project.yml`).
