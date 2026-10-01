# App Store Connect texts

Drafts to paste into App Store Connect. Check them against the build you
submit. Fill in the bracketed parts yourself; demo accounts never go in this
repository.

## App Information and version URLs

- **Marketing URL:** https://icebear.digital/mouselook
- **Support URL:** https://icebear.digital/mouselook (support section: GitHub
  issues and email)
- **Privacy Policy URL:** https://github.com/mattonik/mouselook/blob/main/docs/app-store/privacy-policy.md
  (the website's Privacy entry links to the same file)
- **Price:** USD 9.99, one-time, no in-app purchases

The website's beta button is the TestFlight public link
(https://testflight.apple.com/join/UxsMy829) of the external testing group.
Its tester limit keeps the beta small; raise it in App Store Connect to let
more people in.

## TestFlight ▸ Test Information

**Beta App Description**

Mouselook lets you use Figma on iPad the way you do on a computer: Space + drag
pans, ⌘ + scroll zooms, right-click and keyboard shortcuts work, and dragging a
number field keeps going past the screen edge. Games in GeForce NOW can capture
the mouse for camera control. Needs an iPad with a
mouse or trackpad and a keyboard.

**What to Test**

1. Pick Figma in onboarding, sign in, open one of your files.
2. Hold Space and drag to pan, hold ⌘ and scroll to zoom, and hold Shift and
   scroll to move sideways.
3. Use the keyboard and mouse as on a computer: V, R, T, ⌘D, ⌘G, right-click
   for the context menu, Shift + click to select several layers, ⌥ + drag to
   duplicate.
4. Drag a number field label (X, Y, W, rotation) past the screen edge. The
   value keeps changing instead of stopping at the edge.
5. Switch to GeForce NOW from the ⋯ menu and back; the Figma file reopens.
6. In GeForce NOW, start a game and click into it. The mouse turns the camera
   until you hold Esc for a second.
7. If something doesn't work: ⋯ ▸ Settings ▸ Copy diagnostics, and send it
   with your feedback.

**Feedback email:** mouselook@icebear.sk

## App Review ▸ Notes

Mouselook is a web view for mouse-driven web apps that need pointer lock:
design tools (Figma) and cloud gaming (GeForce NOW). iPadOS WebKit does not
implement the Pointer Lock API, so on iPad these apps cannot capture the mouse.
Mouselook adds it:

- A script injected into the page provides the standard Pointer Lock API
  (`requestPointerLock`, `pointerLockElement`, relative `movementX/Y`).
- While a page holds the lock, the app captures the pointer with
  `prefersPointerLocked` and reads relative motion from `GCMouse` (Game
  Controller framework), then passes it to the page. Holding Esc for one
  second releases the mouse.

The app does not download or run code other than the page the user opens and
the scripts bundled with the app. It collects no data; a local diagnostics log
stays on the device and is only copied to the clipboard when the user taps
"Copy diagnostics".

**Background audio.** Streaming games stop when an app is suspended, and a
quick switch to another app loses the game session. When the user has chosen
"Keep game running in background" (Settings, default 5 minutes, can be Off),
and only while a game is queued or streaming, the app keeps an audio session
active by playing silence mixed with other audio, so the stream's own audio
and connection continue. When the chosen time ends, the app pauses all media
and stops the audio session, and iPadOS suspends it as usual. Nothing plays in
the background outside a game session.

**Third-party services.** Figma and GeForce NOW are opened as their normal
websites; users sign in with their own accounts and subscriptions. Mouselook
is not affiliated with Figma or NVIDIA and does not change or resell their
content.

**To review:**

- Figma: sign in with [demo account], open the file "[file name]", drag the
  "X" label in the right panel to the left past the screen edge.
- GeForce NOW: sign in with [demo account]. Free-tier sessions can wait in a
  queue; a video of a session is at [link].
- A mouse or trackpad is needed to see pointer lock. Without one, the app
  shows a note in onboarding.
