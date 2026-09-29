#!/usr/bin/env python3
"""Host side of DebugBridge.swift: run JavaScript in the app's page.

Simulator (Debug build):

    python3 tools/debug-bridge.py &
    curl -s --data-binary 'return location.href' localhost:8766/eval

Device (Debug build on the same network): the app has the Mac's address and a
token baked in at build time; the server must listen on the LAN and check it.

    TOKEN=$(openssl rand -hex 16)
    xcodebuild ... DEBUG_BRIDGE_URL=http://$(scutil --get LocalHostName).local:8766 \\
        DEBUG_BRIDGE_TOKEN=$TOKEN
    BRIDGE_TOKEN=$TOKEN python3 tools/debug-bridge.py --lan &

With --lan, /next and /result require the token, and /eval only accepts
requests from this Mac itself. The script is an async function body (use
`return`, `await` works); the reply is its JSON-encoded return value, or
"ERROR: ..." if it threw. One script at a time; /eval gives up after 60 s.
"""
import hmac
import http.server
import os
import queue
import sys
import threading

LAN = "--lan" in sys.argv
TOKEN = os.environ.get("BRIDGE_TOKEN", "")
if LAN and not TOKEN:
    sys.exit("--lan needs BRIDGE_TOKEN (the DEBUG_BRIDGE_TOKEN the app was built with)")

scripts = queue.Queue()
results = queue.Queue()
eval_lock = threading.Lock()


class Handler(http.server.BaseHTTPRequestHandler):
    def _reply(self, status, body=b""):
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        return self.rfile.read(int(self.headers.get("Content-Length", 0)))

    def _is_app(self):
        return not TOKEN or hmac.compare_digest(self.headers.get("X-Bridge-Token", ""), TOKEN)

    def _is_local(self):
        return self.client_address[0] in ("127.0.0.1", "::1")

    def do_GET(self):
        if self.path != "/next":
            return self._reply(404)
        if not self._is_app():
            return self._reply(403)
        try:
            script = scripts.get(timeout=25)
        except queue.Empty:
            return self._reply(204)
        try:
            self._reply(200, script)
        except (BrokenPipeError, ConnectionResetError):
            # The poller went away while waiting (the app replaced its
            # browser, which cancels the old poll): hand the script to the
            # next poller instead of losing it.
            scripts.put(script)

    def do_POST(self):
        if self.path == "/result":
            if not self._is_app():
                return self._reply(403)
            results.put(self._body())
            return self._reply(204)
        if self.path != "/eval":
            return self._reply(404)
        if not self._is_local():
            return self._reply(403)
        script = self._body()
        with eval_lock:
            while not results.empty():
                results.get_nowait()
            scripts.put(script)
            try:
                self._reply(200, results.get(timeout=60) + b"\n")
            except queue.Empty:
                self._reply(504, b"timed out: is the Debug app running and connected?\n")

    def log_message(self, *args):
        pass


host = "0.0.0.0" if LAN else "127.0.0.1"
http.server.ThreadingHTTPServer((host, 8766), Handler).serve_forever()
