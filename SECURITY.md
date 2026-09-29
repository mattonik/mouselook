# Security

Please report security problems privately by email to
[martin@icebear.sk](mailto:martin@icebear.sk), not in a public issue. You'll get
an answer within a few days.

Useful to know when looking:

- Mouselook is a WKWebView browser. Pages run in WebKit's normal sandbox; the
  app injects `pointerlock-polyfill.js` and `health-checks.js` into the main
  frame and accepts only small, validated messages back from them.
- The app has no server and collects no data. The diagnostics log stays on the
  device until the user copies it.
- `tools/debug-bridge.py` and `DebugBridge.swift` exist only in Debug builds.
  On a local network the bridge needs a token, and `/eval` is accepted from
  localhost only. Release builds contain neither.
