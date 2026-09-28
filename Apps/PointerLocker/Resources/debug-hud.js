// PointerLocker debug overlay. Injected at document start after the
// polyfill when "Debug overlay" is on. Shows, bottom right:
//
//   lock    page/system lock state and connected mice   (from native)
//   mouse   raw GCMouse events/s (native) vs mousemove/s the page sees
//   input   buttons/keys held and click counts, as the page sees them
//   stream  resolution, fps, codec, bitrate, RTT, jitter, loss, drops
//           (getStats on the page's RTCPeerConnection, e.g. GeForce NOW's)
//
// Native pushes its part with window.__pointerLockerHUD.native({...}).
(() => {
  "use strict";
  if (window.__pointerLockerHUD) return;

  const BUTTON_NAMES = ["L", "M", "R", "B", "F"];

  // Track peer connections from the start, so the page's stream is visible.
  const peers = new Set();
  const NativePeerConnection = window.RTCPeerConnection;
  if (NativePeerConnection) {
    const Wrapped = function RTCPeerConnection(...args) {
      const pc = Reflect.construct(NativePeerConnection, args, new.target || Wrapped);
      peers.add(pc);
      return pc;
    };
    Wrapped.prototype = NativePeerConnection.prototype;
    Object.setPrototypeOf(Wrapped, NativePeerConnection); // statics
    window.RTCPeerConnection = Wrapped;
    if (window.webkitRTCPeerConnection) window.webkitRTCPeerConnection = Wrapped;
  }

  let nativeState = null;
  const held = new Set();
  const keys = new Set();
  const clicks = [0, 0, 0, 0, 0];
  let wheelTicks = 0;
  let moves = 0;
  let moveRate = 0;
  let stream = null;

  const listen = (type, fn) => window.addEventListener(type, fn, { capture: true, passive: true });
  listen("mousedown", (e) => held.add(e.button));
  listen("mouseup", (e) => {
    held.delete(e.button);
    if (e.button >= 0 && e.button < clicks.length) clicks[e.button]++;
  });
  listen("mousemove", () => moves++);
  listen("wheel", () => wheelTicks++);
  listen("keydown", (e) => keys.add(e.code || e.key));
  listen("keyup", (e) => keys.delete(e.code || e.key));
  listen("blur", () => keys.clear());

  setInterval(() => {
    moveRate = moves;
    moves = 0;
  }, 1000);

  // ---------------------------------------------------------------------
  // Stream stats
  // ---------------------------------------------------------------------
  let previous = null; // { at, bytes, lost, received, dropped }

  async function pollStats() {
    for (const pc of peers) {
      if (pc.connectionState === "closed" || pc.signalingState === "closed") {
        peers.delete(pc);
        continue;
      }
      let report;
      try {
        report = await pc.getStats();
      } catch (_) {
        continue;
      }
      let video = null;
      let pair = null;
      const byId = new Map();
      report.forEach((s) => {
        byId.set(s.id, s);
        if (s.type === "inbound-rtp" && (s.kind || s.mediaType) === "video") video = s;
        if (s.type === "candidate-pair" && (s.selected || s.nominated) && s.state === "succeeded") pair = s;
      });
      if (!video) continue;

      const now = performance.now();
      const cur = {
        at: now,
        bytes: video.bytesReceived || 0,
        lost: video.packetsLost || 0,
        received: video.packetsReceived || 0,
        dropped: video.framesDropped || 0,
      };
      const p = previous && previous.at < now ? previous : null;
      const seconds = p ? (now - p.at) / 1000 : 0;
      const lostDelta = p ? cur.lost - p.lost : 0;
      const receivedDelta = p ? cur.received - p.received : 0;
      const codec = byId.get(video.codecId);
      stream = {
        width: video.frameWidth,
        height: video.frameHeight,
        fps: video.framesPerSecond,
        codec: codec ? String(codec.mimeType || "").replace(/^video\//, "") : "?",
        decoder: video.decoderImplementation,
        mbps: seconds ? ((cur.bytes - p.bytes) * 8) / seconds / 1e6 : null,
        lossPct: lostDelta + receivedDelta > 0 ? (100 * lostDelta) / (lostDelta + receivedDelta) : 0,
        droppedPerSec: seconds ? (cur.dropped - p.dropped) / seconds : 0,
        jitterMs: video.jitter != null ? video.jitter * 1000 : null,
        rttMs: pair && pair.currentRoundTripTime != null ? pair.currentRoundTripTime * 1000 : null,
      };
      previous = cur;
      return;
    }
    stream = null;
    previous = null;
  }
  setInterval(pollStats, 1000);

  // ---------------------------------------------------------------------
  // Overlay
  // ---------------------------------------------------------------------
  const box = document.createElement("pre");
  box.id = "pointerlocker-hud";
  box.style.cssText =
    // Bottom right: iPadOS 26 window controls sit top left, the menu bottom left.
    "position:fixed;bottom:8px;right:8px;margin:0;padding:6px 8px;z-index:2147483647;" +
    "pointer-events:none;font:11px/1.35 ui-monospace,Menlo,monospace;color:#b6f58a;" +
    "background:rgba(0,0,0,.65);border-radius:6px;white-space:pre";
  const attach = () => {
    // Last child of <html>, so it paints above an emulated-fullscreen element.
    if (document.documentElement && box.parentNode !== document.documentElement) {
      document.documentElement.appendChild(box);
    }
  };

  const dot = (on) => (on ? "●" : "○");
  const fixed = (v, digits = 1) => (v == null || !isFinite(v) ? "-" : v.toFixed(digits));
  const list = (items) => (items.length ? items.join(" ") : "-");

  function render() {
    attach();
    const n = nativeState;
    const locked = !!(window.__pointerLocker && window.__pointerLocker.isLocked);
    const lines = [
      n
        ? `lock   page ${dot(n.pageLock)}  system ${dot(n.systemLock)}  mice ${n.mice}`
        : `lock   page ${dot(locked)}  (no native data)`,
      `mouse  raw ${n ? n.rawRate : "-"}/s  page ${moveRate}/s`,
      `input  held ${list([...held].sort().map((b) => BUTTON_NAMES[b] || b))}  keys ${list([...keys])}`,
      `       clicks ${BUTTON_NAMES.map((name, i) => name + clicks[i]).join(" ")}  wheel ${wheelTicks}`,
    ];
    if (stream) {
      const s = stream;
      lines.push(
        `stream ${s.width || "?"}x${s.height || "?"} @ ${fixed(s.fps)} fps  ${s.codec}` +
          (s.decoder ? ` (${s.decoder})` : ""),
        `net    ${fixed(s.mbps)} Mbps  rtt ${fixed(s.rttMs, 0)} ms  jitter ${fixed(s.jitterMs)} ms` +
          `  loss ${fixed(s.lossPct, 2)}%  drop ${fixed(s.droppedPerSec)}/s`
      );
    } else {
      lines.push(`stream - (${peers.size} peer connection${peers.size === 1 ? "" : "s"})`);
    }
    box.textContent = lines.join("\n");
  }
  setInterval(render, 500);

  Object.defineProperty(window, "__pointerLockerHUD", {
    value: Object.freeze({
      native(state) {
        nativeState = state;
      },
      render,
      get peerCount() {
        return peers.size;
      },
    }),
  });
})();
