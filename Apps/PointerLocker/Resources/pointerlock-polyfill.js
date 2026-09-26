// pointerlock-polyfill.js
//
// Injected into the page world at document start by BrowserViewController.
//
// WebKit on iPadOS does not implement the Pointer Lock API. This script
// provides the page-facing half of it (requestPointerLock, exitPointerLock,
// pointerLockElement, pointerlockchange/pointerlockerror and movementX/Y on
// mouse/pointer events). The native half (MouseBridge.swift) hides the system
// pointer with UIViewController.prefersPointerLocked, reads raw deltas from
// GCMouse and feeds them in through window.__pointerLocker.batch(...).
//
// Protocol
//   page -> native: webkit.messageHandlers.pointerLocker.postMessage({type})
//     {type: "lock"}    page called requestPointerLock()
//     {type: "unlock"}  lock ended (exitPointerLock, hold-Esc, detach, ...)
//   native -> page: window.__pointerLocker.batch([[kind, ...args], ...])
//     ["m", dx, dy]         relative movement (CSS px, y down)
//     ["b", button, down]   button 0 = primary, 1 = middle, 2 = secondary
//     ["w", dx, dy]         wheel, deltaMode = pixels
//   native -> page: window.__pointerLocker.forceUnlock()
(() => {
  "use strict";
  if (window.__pointerLocker) return;

  const HOLD_ESC_TO_UNLOCK_MS = 1000;
  const config = Object.assign(
    { spoofDesktop: true },
    window.__pointerLockerConfig || {}
  );

  const post = (message) => {
    try {
      window.webkit.messageHandlers.pointerLocker.postMessage(message);
    } catch (_) {
      // Not running inside the app (e.g. the test harness without a stub).
    }
  };

  // ---------------------------------------------------------------------
  // Desktop spoofing. GeForce NOW routes iPads (detected via touch points
  // even with a Mac user agent) to its touch/PWA flow, which never asks for
  // pointer lock. Pretending to be a pointer-only Mac gets the desktop client.
  // ---------------------------------------------------------------------
  if (config.spoofDesktop) {
    try {
      Object.defineProperty(Navigator.prototype, "maxTouchPoints", {
        configurable: true,
        get: () => 0,
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------
  let lockedElement = null;
  let lastX = Math.round(window.innerWidth / 2);
  let lastY = Math.round(window.innerHeight / 2);
  let buttons = 0; // MouseEvent.buttons bitmask
  let escTimer = null;

  // Remember where the real cursor was, so synthetic events carry a
  // plausible clientX/clientY (the spec freezes these while locked).
  window.addEventListener(
    "pointermove",
    (e) => {
      if (!lockedElement && e.isTrusted) {
        lastX = e.clientX;
        lastY = e.clientY;
      }
    },
    { capture: true, passive: true }
  );

  const dispatchDocEvent = (type) => {
    document.dispatchEvent(new Event(type, { bubbles: true }));
  };

  const setLocked = (el) => {
    const previous = lockedElement;
    lockedElement = el;
    if (!el && previous) buttons = 0;
    if (el !== previous) {
      post({ type: el ? "lock" : "unlock" });
      // Real browsers fire this as a task after the state change.
      setTimeout(() => dispatchDocEvent("pointerlockchange"), 0);
    }
  };

  // ---------------------------------------------------------------------
  // API surface
  // ---------------------------------------------------------------------
  function requestPointerLock(_options) {
    const el = this;
    if (!(el instanceof Element) || !el.isConnected) {
      setTimeout(() => dispatchDocEvent("pointerlockerror"), 0);
      return Promise.reject(
        new DOMException("Element is not in a document", "WrongDocumentError")
      );
    }
    setLocked(el);
    return Promise.resolve();
  }

  function exitPointerLock() {
    setLocked(null);
  }

  const defineMethod = (proto, name, fn) => {
    Object.defineProperty(proto, name, {
      configurable: true,
      writable: true,
      value: fn,
    });
  };

  defineMethod(Element.prototype, "requestPointerLock", requestPointerLock);
  defineMethod(Element.prototype, "webkitRequestPointerLock", requestPointerLock);
  defineMethod(Document.prototype, "exitPointerLock", exitPointerLock);
  defineMethod(Document.prototype, "webkitExitPointerLock", exitPointerLock);

  const pointerLockElementGetter = {
    configurable: true,
    get() {
      if (!lockedElement || !lockedElement.isConnected) return null;
      return lockedElement.ownerDocument === this ? lockedElement : null;
    },
  };
  Object.defineProperty(Document.prototype, "pointerLockElement", pointerLockElementGetter);
  Object.defineProperty(Document.prototype, "webkitPointerLockElement", pointerLockElementGetter);
  if (window.ShadowRoot) {
    Object.defineProperty(ShadowRoot.prototype, "pointerLockElement", {
      configurable: true,
      get: () => null,
    });
  }

  // `document.onpointerlockchange = fn` only works if the IDL attribute
  // exists, which it doesn't in iOS WebKit. Emulate event handler attributes.
  for (const type of ["pointerlockchange", "pointerlockerror"]) {
    let handler = null;
    const listener = (e) => {
      if (typeof handler === "function") handler.call(e.currentTarget, e);
    };
    Object.defineProperty(Document.prototype, "on" + type, {
      configurable: true,
      get: () => handler,
      set(fn) {
        if (handler === null && fn != null) document.addEventListener(type, listener);
        if (handler !== null && fn == null) document.removeEventListener(type, listener);
        handler = typeof fn === "function" ? fn : null;
      },
    });
  }

  // Ensure movementX/Y exist on MouseEvent (0 for everything except our
  // synthetic moves) so feature detection like `"movementX" in e` passes.
  for (const prop of ["movementX", "movementY"]) {
    if (!(prop in MouseEvent.prototype)) {
      Object.defineProperty(MouseEvent.prototype, prop, {
        configurable: true,
        get: () => 0,
      });
    }
  }

  // ---------------------------------------------------------------------
  // Swallow real (trusted) mouse/pointer events while locked; the native
  // side delivers clicks through GCMouse instead. Without this a click could
  // be delivered twice if UIKit also forwards it.
  // ---------------------------------------------------------------------
  const SWALLOWED = [
    "pointerdown", "pointerup", "pointermove", "pointerover", "pointerout",
    "pointerenter", "pointerleave", "mousedown", "mouseup", "mousemove",
    "mouseover", "mouseout", "click", "auxclick", "dblclick", "contextmenu",
    "wheel",
  ];
  for (const type of SWALLOWED) {
    window.addEventListener(
      type,
      (e) => {
        if (lockedElement && e.isTrusted && e.pointerType !== "touch") {
          e.stopImmediatePropagation();
          e.preventDefault();
        }
      },
      { capture: true, passive: false }
    );
  }

  // If the locked element leaves the document, the lock ends (per spec).
  new MutationObserver(() => {
    if (lockedElement && !lockedElement.isConnected) setLocked(null);
  }).observe(document, { childList: true, subtree: true });

  // Hold Escape to release the lock (same gesture GeForce NOW uses). A tap
  // on Escape still reaches the page so in-game menus keep working.
  window.addEventListener(
    "keydown",
    (e) => {
      if (e.key !== "Escape" || !lockedElement || e.repeat || escTimer) return;
      escTimer = setTimeout(() => {
        escTimer = null;
        setLocked(null);
      }, HOLD_ESC_TO_UNLOCK_MS);
    },
    true
  );
  window.addEventListener(
    "keyup",
    (e) => {
      if (e.key === "Escape" && escTimer) {
        clearTimeout(escTimer);
        escTimer = null;
      }
    },
    true
  );

  // ---------------------------------------------------------------------
  // Synthetic input
  // ---------------------------------------------------------------------
  const BUTTON_BITS = [1, 4, 2]; // button index -> buttons bit (0=L,1=M,2=R)

  const withMovement = (event, dx, dy) => {
    Object.defineProperty(event, "movementX", { value: dx });
    Object.defineProperty(event, "movementY", { value: dy });
    return event;
  };

  const baseInit = (extra) =>
    Object.assign(
      {
        bubbles: true,
        cancelable: true,
        composed: true,
        view: window,
        clientX: lastX,
        clientY: lastY,
        screenX: lastX,
        screenY: lastY,
        buttons,
      },
      extra
    );

  const pointerInit = (extra) =>
    baseInit(
      Object.assign(
        {
          pointerId: 1,
          pointerType: "mouse",
          isPrimary: true,
          width: 1,
          height: 1,
          pressure: buttons ? 0.5 : 0,
        },
        extra
      )
    );

  const firePointer = (target, type, extra, dx = 0, dy = 0) => {
    if (typeof PointerEvent !== "function") return true;
    const ev = withMovement(new PointerEvent(type, pointerInit(extra)), dx, dy);
    Object.defineProperty(ev, "getCoalescedEvents", { value: () => [ev] });
    Object.defineProperty(ev, "getPredictedEvents", { value: () => [] });
    return target.dispatchEvent(ev);
  };

  const fireMouse = (target, type, extra, dx = 0, dy = 0) =>
    target.dispatchEvent(withMovement(new MouseEvent(type, baseInit(extra)), dx, dy));

  const move = (dx, dy) => {
    const target = lockedElement;
    firePointer(target, "pointermove", { button: -1 }, dx, dy);
    fireMouse(target, "mousemove", { button: 0 }, dx, dy);
  };

  const button = (index, down) => {
    const bit = BUTTON_BITS[index];
    if (bit === undefined) return;
    const target = lockedElement;
    const wasPressed = buttons !== 0;
    if (down === !!(buttons & bit)) return; // no change
    buttons = down ? buttons | bit : buttons & ~bit;

    // Pointer events: down/up only for the first/last button, chords are moves.
    let pointerType;
    if (down) pointerType = wasPressed ? "pointermove" : "pointerdown";
    else pointerType = buttons ? "pointermove" : "pointerup";
    const pointerOk = firePointer(target, pointerType, { button: index });

    // preventDefault on pointerdown suppresses compatibility mouse events.
    if (pointerOk || pointerType !== "pointerdown") {
      fireMouse(target, down ? "mousedown" : "mouseup", { button: index });
    }
    if (down && index === 2) fireMouse(target, "contextmenu", { button: 2 });
    if (!down) fireMouse(target, index === 0 ? "click" : "auxclick", { button: index });
  };

  const wheel = (dx, dy) => {
    if (typeof WheelEvent !== "function") return;
    lockedElement.dispatchEvent(
      new WheelEvent("wheel", baseInit({ deltaX: dx, deltaY: dy, deltaZ: 0, deltaMode: 0 }))
    );
  };

  const api = {
    batch(events) {
      for (const [kind, a, b] of events) {
        if (!lockedElement) return;
        if (kind === "m") move(a, b);
        else if (kind === "b") button(a, b);
        else if (kind === "w") wheel(a, b);
      }
    },
    forceUnlock() {
      setLocked(null);
    },
    get isLocked() {
      return !!lockedElement;
    },
  };
  Object.defineProperty(window, "__pointerLocker", { value: Object.freeze(api) });
})();
