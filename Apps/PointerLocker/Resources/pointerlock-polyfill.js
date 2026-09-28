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
  // Set by the app from the active service profile (ServiceProfile.swift).
  //   identity: { platform?, maxTouchPoints? }  what the page should see
  const config = Object.assign({ identity: null }, window.__pointerLockerConfig || {});

  const post = (message) => {
    try {
      window.webkit.messageHandlers.pointerLocker.postMessage(message);
    } catch (_) {
      // Not running inside the app (e.g. the test harness without a stub).
    }
  };

  // ---------------------------------------------------------------------
  // Browser identity. Services pick their client by device: GeForce NOW sends
  // an iPad (touch points, "iPad" platform) to its touch/PWA flow, which never
  // asks for pointer lock. The profile says what to report instead; the user
  // agent itself is set natively.
  // ---------------------------------------------------------------------
  const identity = config.identity;
  if (identity) {
    const override = (proto, name, value) => {
      try {
        Object.defineProperty(proto, name, { configurable: true, get: () => value });
      } catch (_) {}
    };
    if (identity.maxTouchPoints != null) override(Navigator.prototype, "maxTouchPoints", identity.maxTouchPoints);
    if (identity.platform != null) {
      override(Navigator.prototype, "platform", identity.platform);
      spoofWorkers(identity.platform);
    }
  }

  // User scripts don't run inside workers, and WKWebView reports "iPad" there
  // even in desktop mode. GeForce NOW reads navigator.platform from a worker
  // (built from a Blob URL it revokes at once) and shows its iPad "Add to Home
  // Screen" wall. So prepend a prelude to every worker script. Blob URLs are
  // resolved to their Blob when created, which keeps this synchronous and
  // immune to the immediate revoke.
  function spoofWorkers(platform) {
    const prelude =
      "try{Object.defineProperty(WorkerNavigator.prototype,'platform'," +
      `{configurable:true,get:()=>${JSON.stringify(platform)}})}catch(_){}\n`;
    const blobs = new Map();
    const createObjectURL = URL.createObjectURL;
    const revokeObjectURL = URL.revokeObjectURL;
    URL.createObjectURL = function (obj) {
      const url = createObjectURL.apply(this, arguments);
      if (obj instanceof Blob) blobs.set(url, obj);
      return url;
    };
    URL.revokeObjectURL = function (url) {
      blobs.delete(String(url));
      return revokeObjectURL.apply(this, arguments);
    };

    const wrapScript = (scriptURL, options) => {
      const href = String(scriptURL);
      const isModule = options && options.type === "module";
      let parts;
      if (blobs.has(href)) {
        parts = [prelude, blobs.get(href)];
      } else {
        const abs = new URL(href, document.baseURI).href;
        // Only same-origin scripts can be re-hosted in a Blob worker.
        if (abs.startsWith("data:") || new URL(abs).origin !== location.origin) return scriptURL;
        parts = [prelude, isModule
          ? `import ${JSON.stringify(abs)};`
          : `importScripts(${JSON.stringify(abs)});`];
      }
      return createObjectURL(new Blob(parts, { type: "text/javascript" }));
    };

    for (const name of ["Worker", "SharedWorker"]) {
      const Native = window[name];
      if (!Native) continue;
      const Wrapped = function (scriptURL, options) {
        if (!new.target) return Native(scriptURL, options); // throws like native
        let url = scriptURL;
        try { url = wrapScript(scriptURL, options); } catch (_) {}
        return Reflect.construct(Native, [url, options], new.target);
      };
      Wrapped.prototype = Native.prototype;
      Object.defineProperty(Wrapped, "name", { value: name });
      window[name] = Wrapped;
    }
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
    // Release held buttons while the element still gets them, highest first,
    // or the game keeps firing/aiming. Not a click: no click/auxclick.
    if (!el && previous) {
      for (let i = BUTTON_BITS.length - 1; i >= 0; i--) {
        if (buttons & BUTTON_BITS[i]) button(i, false, { click: false });
      }
      buttons = 0;
    }
    lockedElement = el;
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

  // Keys held when the page loses focus (app switch, dialog, ⌘-Tab) never
  // get their keyup, so the game would keep walking. Release them.
  const heldKeys = new Map(); // code -> { key, code, keyCode }
  window.addEventListener("keydown", (e) => {
    if (e.isTrusted) heldKeys.set(e.code, { key: e.key, code: e.code, keyCode: e.keyCode });
  }, true);
  window.addEventListener("keyup", (e) => {
    if (e.isTrusted) heldKeys.delete(e.code);
  }, true);
  const releaseKeys = () => {
    if (!heldKeys.size) return;
    const keys = [...heldKeys.values()];
    heldKeys.clear();
    const target = document.activeElement || document.body || document;
    for (const { key, code, keyCode } of keys) {
      const e = new KeyboardEvent("keyup", { key, code, bubbles: true, cancelable: true, composed: true });
      for (const p of ["keyCode", "which"]) Object.defineProperty(e, p, { get: () => keyCode });
      target.dispatchEvent(e);
    }
  };
  window.addEventListener("blur", releaseKeys);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") releaseKeys();
  });

  // iPadOS WebKit leaves metaKey/ctrlKey/altKey/shiftKey false on wheel
  // events even while the key is held (so ⌘ + scroll pans instead of
  // zooming), and our synthetic events never set them. Mouse, pointer and
  // wheel events report a modifier as held if the keyboard says it is.
  const heldModifier = (key) => {
    for (const k of heldKeys.values()) if (k.key === key) return true;
    return false;
  };
  for (const [prop, key] of [["metaKey", "Meta"], ["ctrlKey", "Control"], ["altKey", "Alt"], ["shiftKey", "Shift"]]) {
    const native = Object.getOwnPropertyDescriptor(MouseEvent.prototype, prop);
    if (!native || !native.get) continue;
    Object.defineProperty(MouseEvent.prototype, prop, {
      configurable: true,
      enumerable: native.enumerable,
      get() {
        return native.get.call(this) || heldModifier(key);
      },
    });
  }

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
  // Fullscreen API, emulated in-page. The app is already full screen, and
  // native element fullscreen moves the WKWebView into WebKit's own window:
  // the app's view controller (and its prefersPointerLocked) is no longer in
  // charge, and on exit the web view comes back at 0x0. So pin the element
  // over the viewport with CSS instead and report it as the fullscreen one.
  // ---------------------------------------------------------------------
  const FULLSCREEN_ATTR = "data-pointerlocker-fullscreen";
  let fullscreenElement = null;

  const fullscreenStyle = document.createElement("style");
  fullscreenStyle.textContent =
    `[${FULLSCREEN_ATTR}]{position:fixed!important;inset:0!important;` +
    "width:100vw!important;height:100vh!important;max-width:none!important;" +
    "max-height:none!important;margin:0!important;box-sizing:border-box!important;" +
    "z-index:2147483647!important;transform:none!important}";
  const attachFullscreenStyle = () =>
    (document.head || document.documentElement).appendChild(fullscreenStyle);
  if (document.documentElement) attachFullscreenStyle();
  else document.addEventListener("DOMContentLoaded", attachFullscreenStyle, { once: true });

  const setFullscreen = (el) => {
    const previous = fullscreenElement;
    if (el === previous) return;
    if (previous) previous.removeAttribute(FULLSCREEN_ATTR);
    if (el) el.setAttribute(FULLSCREEN_ATTR, "");
    fullscreenElement = el;
    if (!fullscreenStyle.isConnected) attachFullscreenStyle();
    const target = el || previous;
    setTimeout(() => {
      // Fired at the element (bubbling to the document), or at the document
      // if the element has since been removed, like real browsers.
      const at = target.isConnected ? target : document;
      for (const type of ["fullscreenchange", "webkitfullscreenchange"]) {
        at.dispatchEvent(new Event(type, { bubbles: true, composed: true }));
      }
    }, 0);
  };

  function requestFullscreen() {
    if (!(this instanceof Element) || !this.isConnected) {
      setTimeout(() => document.dispatchEvent(new Event("fullscreenerror", { bubbles: true })), 0);
      return Promise.reject(new TypeError("Element is not in a document"));
    }
    setFullscreen(this);
    return Promise.resolve();
  }

  function exitFullscreen() {
    setFullscreen(null);
    return Promise.resolve();
  }

  for (const name of ["requestFullscreen", "webkitRequestFullscreen", "webkitRequestFullScreen"]) {
    defineMethod(Element.prototype, name, requestFullscreen);
  }
  for (const name of ["exitFullscreen", "webkitExitFullscreen", "webkitCancelFullScreen"]) {
    defineMethod(Document.prototype, name, exitFullscreen);
  }
  const fullscreenGetters = {
    fullscreenElement: () => fullscreenElement,
    webkitFullscreenElement: () => fullscreenElement,
    webkitCurrentFullScreenElement: () => fullscreenElement,
    fullscreen: () => !!fullscreenElement,
    webkitIsFullScreen: () => !!fullscreenElement,
    fullscreenEnabled: () => true,
    webkitFullscreenEnabled: () => true,
  };
  for (const [name, get] of Object.entries(fullscreenGetters)) {
    Object.defineProperty(Document.prototype, name, { configurable: true, get });
  }

  new MutationObserver(() => {
    if (fullscreenElement && !fullscreenElement.isConnected) setFullscreen(null);
  }).observe(document, { childList: true, subtree: true });

  // ---------------------------------------------------------------------
  // Synthetic input
  // ---------------------------------------------------------------------
  // button index -> buttons bit (0=L, 1=M, 2=R, 3=back, 4=forward)
  const BUTTON_BITS = [1, 4, 2, 8, 16];

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

  const button = (index, down, { click = true } = {}) => {
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
    if (!down && click) fireMouse(target, index === 0 ? "click" : "auxclick", { button: index });
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
