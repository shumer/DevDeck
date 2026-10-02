"""Disposable WSL boundary probe; no production projects or credentials are used."""
import argparse
import http.server
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid


def serve(folder, marker):
    # A harmless child exercises session-wide termination, like a dev-server wrapper.
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(3600)"])
    Path(folder, "child").write_text(str(child.pid))
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = json.dumps({"probe": marker}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            print(fmt % args, flush=True)

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    Path(folder, "port").write_text(str(server.server_port))
    print("Demo listening on " + str(server.server_port), flush=True)
    server.serve_forever()


class Demo:
    def __init__(self):
        self.folder = Path(tempfile.mkdtemp(prefix="devdeck-windows-probe-"))
        self.marker = str(uuid.uuid4())
        self.process = None
        self.url = None

    def health(self):
        if not self.url:
            return False
        try:
            with urllib.request.urlopen(self.url, timeout=2) as response:
                return json.load(response).get("probe") == self.marker
        except Exception:
            return False

    def status(self):
        return {"running": self.health(), "pid": self.process.pid if self.process else None,
                "childAlive": self.child_alive(),
                "url": self.url, "marker": self.marker, "folder": str(self.folder),
                "logs": (self.folder / "server.log").read_text(errors="replace")[-4000:]
                if (self.folder / "server.log").exists() else "No demo started yet."}

    def child_alive(self):
        try:
            pid = int((self.folder / "child").read_text())
            state = Path("/proc", str(pid), "stat").read_text().rsplit(")", 1)[1].split()[0]
            return state not in ("Z", "X")
        except (FileNotFoundError, ValueError):
            return False

    def start(self):
        if self.process and self.process.poll() is None:
            return self.status()
        port_file = self.folder / "port"
        port_file.unlink(missing_ok=True)
        with (self.folder / "server.log").open("a") as log:
            self.process = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), "--serve", str(self.folder), self.marker],
                stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        for _ in range(100):
            if port_file.exists():
                self.url = "http://127.0.0.1:" + port_file.read_text().strip() + "/health"
                if self.health():
                    return self.status()
            if self.process.poll() is not None:
                raise RuntimeError("Demo process exited during startup")
            time.sleep(0.05)
        self.stop()
        raise TimeoutError("Demo did not become healthy")

    def stop(self):
        # The live Popen handle owns this session; never kill a PID read from an arbitrary file.
        if self.process and self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(timeout=3)
        self.process = None
        for _ in range(30):
            if not self.child_alive():
                break
            time.sleep(0.05)
        return self.status()

    def dispatch(self, action):
        if action == "status":
            return self.status()
        if action == "start":
            return self.start()
        if action == "stop":
            return self.stop()
        if action == "restart":
            self.stop()
            return self.start()
        if action == "environment":
            result = subprocess.run(["docker", "version", "--format", "{{.Server.Version}}"],
                                    capture_output=True, text=True, timeout=15)
            return {"dockerReady": result.returncode == 0, "dockerVersion": result.stdout.strip(),
                    "architecture": os.uname().machine, "python": sys.version.split()[0]}
        raise ValueError("Unsupported action: " + str(action))


def main():
    demo = Demo()
    try:
        for line in sys.stdin:
            request = {}
            try:
                request = json.loads(line)
                if not isinstance(request, dict):
                    request = {}
                    raise ValueError("Request must be an object")
                result = demo.dispatch(request.get("action"))
                response = {"id": request.get("id"), "ok": True, "result": result, "protocol": 1}
            except Exception as error:
                response = {"id": request.get("id"), "ok": False, "error": str(error), "protocol": 1}
            print(json.dumps(response), flush=True)
    finally:
        # EOF must leave no disposable server behind, including when the Windows UI exits.
        demo.stop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--serve", nargs=2)
    args = parser.parse_args()
    if args.serve:
        serve(*args.serve)
    else:
        main()
