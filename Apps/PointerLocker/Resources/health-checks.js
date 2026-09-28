// Mouselook health checks. Each check watches the page for one sign that a
// service changed how it treats this browser, and reports once per page load:
//   page -> native: {type: "health", check, result: "ok" | "problem", code}
// Checks only observe: they never change the page or stop its events.
// Set by the app before this script (HealthCheck.swift):
//   window.__mouselookHealth = { checks: [...ids], phase: () => 0 | 1 | 2 }
(() => {
  "use strict";
  const config = window.__mouselookHealth;
  if (!config || window.__mouselookHealthInstalled) return;
  window.__mouselookHealthInstalled = true;

  const reported = new Set();
  const report = (check, result, code) => {
    if (reported.has(check)) return; // once per check per page load
    reported.add(check);
    try {
      window.webkit.messageHandlers.pointerLocker.postMessage({ type: "health", check, result, code });
    } catch (_) {}
  };
  const phase = () => {
    try { return config.phase(); } catch (_) { return 0; }
  };

  // Every lock request, whichever path (WebKit's or the polyfill's) serves it.
  const lockListeners = [];
  for (const name of ["requestPointerLock", "webkitRequestPointerLock"]) {
    const original = Element.prototype[name];
    if (typeof original !== "function") continue;
    Object.defineProperty(Element.prototype, name, {
      configurable: true,
      writable: true,
      value: function (...args) {
        for (const listener of lockListeners) {
          try { listener(this); } catch (_) {}
        }
        return original.apply(this, args);
      },
    });
  }
  const onLockRequest = (listener) => lockListeners.push(listener);

  const checks = {
    // GeForce NOW: its iPad/touch flow means it didn't see a desktop browser.
    "desktop-client"() {
      const ipadFlow = /Add to Home Screen|partially supported/i;
      const seen = () => !!document.body && ipadFlow.test(document.body.innerText);
      let scheduled = false;
      const observer = new MutationObserver(() => {
        if (scheduled) return;
        scheduled = true;
        setTimeout(() => {
          scheduled = false;
          if (seen()) { observer.disconnect(); report("desktop-client", "problem", "ipad-flow"); }
        }, 500);
      });
      const start = () => {
        if (seen()) return report("desktop-client", "problem", "ipad-flow");
        observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
        setTimeout(() => {
          observer.disconnect();
          if (seen()) report("desktop-client", "problem", "ipad-flow");
          else report("desktop-client", "ok", "desktop");
        }, config.desktopClientOkAfterMs ?? 10000);
      };
      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
      else start();
    },

    // Play services: clicking into a playing stream should make the game ask
    // for the mouse. One miss is normal (menus); two in a row is not.
    "lock-on-click"() {
      let misses = 0;
      let waiting = null;
      onLockRequest(() => {
        if (waiting) { clearTimeout(waiting); waiting = null; }
        misses = 0;
        if (phase() === 2) report("lock-on-click", "ok", "locked");
      });
      window.addEventListener("pointerdown", (e) => {
        if (!e.isTrusted || e.button !== 0 || e.pointerType === "touch") return;
        if (waiting || document.pointerLockElement || phase() !== 2) return;
        const onVideo = document.elementsFromPoint(e.clientX, e.clientY).some((el) => el.tagName === "VIDEO");
        if (!onVideo) return;
        waiting = setTimeout(() => {
          waiting = null;
          misses += 1;
          if (misses >= 2) report("lock-on-click", "problem", "no-request");
        }, config.lockWaitMs ?? 2000);
      }, true);
    },

    // Figma: dragging a number's scrub label should request the lock.
    "scrub-lock"() {
      // Older fields sit in "scrubbable" containers; newer ones have hashed
      // class names, so also accept a left-right resize cursor on the label
      // (or just above it) with a number field in the same short row. The
      // row height keeps panel resize handles, which share the cursor and
      // sit in panels full of fields, from counting.
      const isScrubLabel = (target) => {
        if (!(target instanceof Element)) return false;
        if (target.closest('[class*="scrubbable"]')) return true;
        let el = target;
        let resizeCursor = false;
        for (let i = 0; el && i < 3; i++, el = el.parentElement) {
          if (/^(ew|col)-resize$/.test(getComputedStyle(el).cursor)) { resizeCursor = true; break; }
        }
        if (!resizeCursor) return false;
        el = target;
        for (let i = 0; el && i < 3; i++, el = el.parentElement) {
          if (el.getBoundingClientRect().height <= 64 && el.querySelector("input")) return true;
        }
        return false;
      };
      let press = null;
      window.addEventListener("pointerdown", (e) => {
        if (!e.isTrusted || e.button !== 0 || e.pointerType === "touch") { press = null; return; }
        const onScrub = isScrubLabel(e.target);
        press = onScrub ? { x: e.clientX, y: e.clientY, requested: false, timer: null } : null;
      }, true);
      onLockRequest(() => {
        if (!press) return;
        press.requested = true;
        clearTimeout(press.timer);
        report("scrub-lock", "ok", "locked");
      });
      window.addEventListener("pointerup", () => { press = null; }, true);
      window.addEventListener("pointermove", (e) => {
        const p = press;
        if (!p || p.timer || p.requested || !(e.buttons & 1)) return;
        if (Math.hypot(e.clientX - p.x, e.clientY - p.y) <= 3) return;
        p.timer = setTimeout(() => {
          if (!p.requested) report("scrub-lock", "problem", "no-request");
        }, config.scrubWaitMs ?? 500);
      }, true);
    },
  };

  for (const id of config.checks || []) {
    try { checks[id] && checks[id](); } catch (_) {}
  }
})();
