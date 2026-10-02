#!/usr/bin/env python3
"""Exercise worker actions/EOF/cancellation with a fake DDEV CLI in an owned temporary folder."""
import argparse
import json
import os
from pathlib import Path
import select
import shlex
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("--distribution", default="LifecycleSmoke")
parser.add_argument("--report", type=Path)
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ["--"] else args.command
checks = []

with tempfile.TemporaryDirectory(prefix="devdeck lifecycle spaces ") as temporary:
    root = Path(temporary)
    (root / ".ddev").mkdir()
    (root / ".ddev/config.yaml").write_text("name: devdeck-smoke\ntype: php\n")
    (root / "state").write_text("stopped")
    binary = root / "bin"
    binary.mkdir()
    stub = r'''#!/usr/bin/env python3
import json, os, signal, subprocess, sys, time
from pathlib import Path
root = Path(os.environ["DEVDECK_SMOKE_ROOT"])
args = sys.argv[1:]
if args[:2] == ["list", "-j"]:
    print(json.dumps({"raw":[{"name":"devdeck-smoke", "approot":str(root), "type":"php", "status":(root/"state").read_text()}]}))
elif args and args[0] == "logs":
    print("owned fixture log")
elif args and args[0] in ("start", "stop", "restart"):
    print("owned action progress", flush=True)
    with (root/"commands").open("a") as out: out.write(args[0]+"\n")
    if (root/"stall").exists():
        (root/"parent.pid").write_text(str(os.getpid()))
        child = subprocess.Popen([sys.executable,"-c","import os,signal,time; from pathlib import Path; signal.signal(signal.SIGTERM,signal.SIG_IGN); Path(os.environ['DEVDECK_SMOKE_ROOT']+'/child.pid').write_text(str(os.getpid())); time.sleep(90)"])
        child.wait()
    else:
        (root/"state").write_text("stopped" if args[0]=="stop" else "running")
else: sys.exit(2)
'''
    (binary / "ddev").write_text(stub)
    (binary / "docker").write_text("#!/bin/sh\nprintf '28.4.0\\n'\n")
    for name in ("ddev", "docker"):
        (binary / name).chmod(0o755)
    # Isolate shell profile discovery from the user's real startup files and tool installations.
    shell = binary / "shell"
    shell.write_text("#!/bin/sh\nexec /bin/bash --noprofile --norc -c \"$2\"\n")
    shell.chmod(0o755)
    environment = dict(os.environ, DEVDECK_SMOKE_ROOT=str(root), DEVDECK_WORKER_TEST_SHELL=str(shell),
                       PATH=str(binary) + ":/usr/bin:/bin", DEVDECK_ALLOW_TEST_SHELL="1")
    reference = {"id": "ddev.project.smoke", "distribution": args.distribution, "kind": "ddev", "path": str(root)}

    def launch():
        return subprocess.Popen(command, env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)

    def send(worker, identifier, operation, **extra):
        request = {"protocolVersion": 1, "id": identifier, "operation": operation, **extra}
        if operation.startswith("project."): request["project"] = reference
        worker.stdin.write(json.dumps(request).encode() + b"\n")
        worker.stdin.flush()

    def receive(worker, timeout=10):
        end = time.monotonic() + timeout
        while True:
            readable, _, _ = select.select([worker.stdout], [], [], max(0, end - time.monotonic()))
            assert readable, "worker response deadline"
            line = worker.stdout.readline()
            assert line, "worker unexpectedly closed output"
            response = json.loads(line)
            if "event" not in response: return response
            assert response["event"]["kind"] == "progress"
            checks.append({"check": "correlated CLI progress", "passed": True})

    def check(label, value):
        assert value, label
        checks.append({"check": label, "passed": True})

    def await_pid(name):
        for _ in range(300):
            file = root / name
            if file.exists(): return int(file.read_text())
            time.sleep(0.01)
        raise AssertionError("fixture pid missing")

    def dead(pid):
        try:
            text = Path(f"/proc/{pid}/status").read_text()
            return any(line.startswith("State:") and "Z" in line for line in text.splitlines())
        except FileNotFoundError:
            return True

    worker = launch()
    try:
        for action, expected in [("start", "running"), ("restart", "running"), ("stop", "stopped")]:
            send(worker, action, "project." + action)
            response = receive(worker)
            check("verified " + action, response.get("status", {}).get("state") == expected)
        send(worker, "logs", "project.logs")
        check("logs use existing DDEV service", "owned fixture log" in receive(worker).get("logs", {}).get("lines", []))
        (root / "stall").touch()
        send(worker, "slow", "project.start")
        parent, child = await_pid("parent.pid"), await_pid("child.pid")
        send(worker, "busy", "project.stop")
        check("same-project mutation rejected", receive(worker).get("error", {}).get("code") == "projectBusy")
        send(worker, "cancel", "cancel", targetRequestID="slow")
        responses = [receive(worker), receive(worker)]
        check("cancel acknowledged", any(row.get("id") == "cancel" and not row.get("error") for row in responses))
        check("operation reports cancellation", any(row.get("id") == "slow" and row.get("error", {}).get("code") == "cancelled" for row in responses))
        check("cancelled parent and child are dead", dead(parent) and dead(child))
        (root / "stall").unlink()
        send(worker, "recovered", "project.status")
        check("worker reusable after cancellation", receive(worker).get("status", {}).get("state") == "stopped")
        for name in ("parent.pid", "child.pid"): (root / name).unlink(missing_ok=True)
        (root / "stall").touch()
        send(worker, "eof", "project.start")
        parent, child = await_pid("parent.pid"), await_pid("child.pid")
        worker.stdin.close()
        worker.wait(timeout=5)
        check("EOF cancels active session and exits", worker.returncode == 0 and dead(parent) and dead(child))
    finally:
        if worker.poll() is None:
            worker.stdin.close()
            try: worker.wait(timeout=5)
            except subprocess.TimeoutExpired: worker.kill(); worker.wait(timeout=5)
    report = {"passed": len(checks), "failed": 0, "fixtureOnly": True, "checks": checks}
    if args.report: args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Worker lifecycle: {len(checks)} passed, 0 failed; only owned fixture processes.")
