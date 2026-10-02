"""Windows-to-WSL live Compose probe using only an owned disposable stack."""
import argparse
import concurrent.futures
import datetime
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid


def read_health(url, marker):
    if not url:
        return False
    try:
        with urllib.request.urlopen(url, timeout=3) as response:
            return json.load(response).get("probe") == marker
    except Exception:
        return False


class ComposeStack:
    def __init__(self):
        self.project = "devdeck-probe-" + uuid.uuid4().hex[:12]
        self.marker = str(uuid.uuid4())
        self.folder = Path(tempfile.mkdtemp(prefix=self.project + "-"))
        web = self.folder / "site with spaces"
        web.mkdir()
        (web / "health.json").write_text(json.dumps({"probe": self.marker}))
        self.image = "python:3.12-alpine"
        self.url = None
        # JSON is valid Compose input and avoids adding a YAML dependency to the probe.
        config = {"services": {"web": {
            "image": self.image,
            "command": ["python", "-u", "-m", "http.server", "8080", "--directory", "/srv"],
            "ports": [{"target": 8080, "published": "0", "host_ip": "127.0.0.1"}],
            "volumes": [{"type": "bind", "source": str(web), "target": "/srv", "read_only": True}],
            "labels": {"devdeck.probe": self.marker},
        }}}
        self.config = self.folder / "compose.json"
        self.config.write_text(json.dumps(config))

    def compose(self, *args, timeout=90):
        result = subprocess.run(
            ["docker", "compose", "--project-directory", str(self.folder),
             "--file", str(self.config), "--project-name", self.project, *args],
            capture_output=True, text=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        return result.stdout

    def inspect(self):
        ids = self.compose("ps", "--all", "--quiet").split()
        if not ids:
            return []
        output = subprocess.run(["docker", "inspect", *ids], capture_output=True,
                                text=True, check=True, timeout=15)
        return json.loads(output.stdout)

    def status(self):
        containers = self.inspect()
        return {"running": read_health(self.url, self.marker), "url": self.url,
                "marker": self.marker, "project": self.project, "folder": str(self.folder),
                "containerCount": len(containers),
                "containers": [{"id": row["Id"], "state": row["State"]["Status"],
                                "startedAt": row["State"]["StartedAt"],
                                "composeDirectory": row["Config"]["Labels"].get("com.docker.compose.project.working_dir"),
                                "probeLabel": row["Config"]["Labels"].get("devdeck.probe"),
                                "mounts": [{"source": mount["Source"], "destination": mount["Destination"],
                                            "readOnly": not mount["RW"]} for mount in row["Mounts"]]}
                               for row in containers],
                "logs": self.compose("logs", "--no-color", "--tail", "10")[-4000:]}

    def wait_ready(self):
        address = self.compose("port", "web", "8080").strip()
        if not address.startswith("127.0.0.1:"):
            raise RuntimeError("Probe port was not bound to loopback: " + address)
        self.url = "http://" + address + "/health.json"
        for _ in range(60):
            if read_health(self.url, self.marker):
                return self.status()
            time.sleep(0.2)
        raise TimeoutError("Compose server failed its health check")

    def dispatch(self, action):
        if action == "environment":
            daemon = subprocess.run(["docker", "version", "--format", "{{.Server.Version}}"],
                                    capture_output=True, text=True, timeout=15)
            return {"dockerReady": daemon.returncode == 0, "dockerVersion": daemon.stdout.strip(),
                    "composeVersion": self.compose("version", "--short").strip(),
                    "architecture": platform.machine(), "image": self.image}
        if action == "status":
            return self.status()
        if action == "start":
            self.compose("up", "--detach", timeout=120)
            return self.wait_ready()
        if action == "restart":
            self.compose("restart", "--timeout", "5")
            return self.wait_ready()
        if action == "stop":
            self.compose("stop", "--timeout", "5")
            return self.status()
        if action == "down":
            self.compose("down", "--timeout", "5")
            return self.status()
        raise ValueError("Unsupported action")


def linux_worker():
    stack = ComposeStack()
    try:
        for line in sys.stdin:
            request = {}
            try:
                request = json.loads(line)
                result = stack.dispatch(request["action"])
                response = {"id": request["id"], "ok": True, "result": result, "protocol": 1}
            except Exception as error:
                response = {"id": request.get("id"), "ok": False, "error": str(error), "protocol": 1}
            print(json.dumps(response), flush=True)
    finally:
        # Project name and config were generated here, so this never targets an existing stack.
        try:
            stack.compose("down", "--timeout", "5")
        except Exception as error:
            print("Probe cleanup failed: " + str(error), file=sys.stderr, flush=True)
            raise


def windows_verify(args):
    if os.name != "nt":
        raise RuntimeError("Run the verifier with Windows Python; use --linux-worker only inside WSL")
    results = []
    summary = {}
    process = subprocess.Popen(
        ["wsl.exe", "--distribution", args.distribution, "--exec", "python3", "-u",
         args.worker, "--linux-worker"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, encoding="utf-8", creationflags=subprocess.CREATE_NO_WINDOW)
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=2)
    errors = pool.submit(process.stderr.read)
    sequence = 0
    exit_code = 0

    def call(action):
        nonlocal sequence
        sequence += 1
        process.stdin.write(json.dumps({"id": sequence, "action": action}) + "\n")
        process.stdin.flush()
        line = pool.submit(process.stdout.readline).result(timeout=180)
        if not line:
            raise RuntimeError("Worker exited: " + errors.result(timeout=5))
        response = json.loads(line)
        if response["id"] != sequence or response["protocol"] != 1:
            raise RuntimeError("Protocol mismatch")
        if not response["ok"]:
            raise RuntimeError(response["error"])
        return response["result"]

    def check(name, passed):
        results.append({"name": name, "passed": bool(passed)})
        print(("PASS " if passed else "FAIL ") + name, flush=True)
        if not passed:
            raise AssertionError(name)

    try:
        summary["environment"] = call("environment")
        check("Docker and Compose answer through WSL protocol", summary["environment"]["dockerReady"])
        check("Probe initially has no containers", call("status")["containerCount"] == 0)
        started = call("start")
        summary["project"] = started["project"]
        summary["folder"] = started["folder"]
        check("Compose start passes WSL health check", started["running"])
        check("Windows reaches the container via localhost", read_health(started["url"], started["marker"]))
        check("Exactly one owned container exists", started["containerCount"] == 1 and
              started["containers"][0]["probeLabel"] == started["marker"])
        container = started["containers"][0]
        check("Compose directory is the Linux project path", container["composeDirectory"] == started["folder"])
        check("Read-only WSL bind mount handles a path containing spaces", any(
            mount["source"] == started["folder"] + "/site with spaces" and mount["readOnly"]
            for mount in container["mounts"]))
        check("Starting again reuses the container", call("start")["containers"][0]["id"] == container["id"])
        check("Container logs contain health requests", "GET /health.json" in call("status")["logs"])
        restarted = call("restart")
        check("Restart changes startup time and restores health", restarted["running"] and
              restarted["containers"][0]["startedAt"] != container["startedAt"])
        check("Windows access works after restart", read_health(restarted["url"], restarted["marker"]))
        stopped = call("stop")
        check("Stop leaves an exited container with no health response", not stopped["running"] and
              stopped["containers"][0]["state"] == "exited")
        check("Start works after stop", call("start")["running"])
        removed = call("down")
        check("Down removes the owned container and health endpoint", removed["containerCount"] == 0 and not removed["running"])
    except Exception as error:
        exit_code = 1
        results.append({"name": "failure", "error": str(error)})
        print("FAIL " + str(error), flush=True)
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=45)
            stderr = errors.result(timeout=5)
            if process.returncode != 0:
                exit_code = 1
                results.append({"name": "cleanup", "passed": False, "error": stderr})
        except Exception as error:
            exit_code = 1
            results.append({"name": "cleanup", "passed": False, "error": str(error)})
            process.kill()
        pool.shutdown(wait=False, cancel_futures=True)
        report = {"date": datetime.date.today().isoformat(), "distribution": args.distribution,
                  "windowsArchitecture": platform.machine(), **summary, "results": results}
        Path(args.report).write_text(json.dumps(report, indent=2), encoding="utf-8")
    return exit_code


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--linux-worker", action="store_true")
    parser.add_argument("--distribution", default="Ubuntu-24.04")
    parser.add_argument("--worker", default="/home/ashumenko/Projects/DevDeck/Tools/WindowsProbe/verify_compose.py")
    parser.add_argument("--report", default=".local_docs/windows-compose-results.json")
    options = parser.parse_args()
    if options.linux_worker:
        linux_worker()
    else:
        sys.exit(windows_verify(options))
