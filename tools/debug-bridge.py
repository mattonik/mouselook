#!/usr/bin/env python3
"""Host side of DebugBridge.swift: run JavaScript in the simulator's page.

    python3 tools/debug-bridge.py &
    curl -s --data-binary 'return location.href' localhost:8766/eval

The script is an async function body (use `return`, `await` works); the reply
is its JSON-encoded return value, or "ERROR: ..." if it threw. One script at a
time; /eval gives up after 60 s if the app isn't running.
"""
import http.server
import queue
import threading

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

    def do_GET(self):
        if self.path != "/next":
            return self._reply(404)
        try:
            self._reply(200, scripts.get(timeout=25))
        except queue.Empty:
            self._reply(204)

    def do_POST(self):
        if self.path == "/result":
            results.put(self._body())
            return self._reply(204)
        if self.path != "/eval":
            return self._reply(404)
        script = self._body()
        with eval_lock:
            while not results.empty():
                results.get_nowait()
            scripts.put(script)
            try:
                self._reply(200, results.get(timeout=60) + b"\n")
            except queue.Empty:
                self._reply(504, b"timed out: is the Debug app running in the simulator?\n")

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", 8766), Handler).serve_forever()
