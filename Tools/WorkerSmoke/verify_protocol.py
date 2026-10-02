#!/usr/bin/env python3
"""Exercise an actual worker transport without starting or querying existing projects."""
import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--distribution", default="ProtocolSmoke")
    parser.add_argument("--report", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("provide the worker command after --")

    def request(identifier, operation="hello", **fields):
        return {"protocolVersion": 1, "id": identifier, "operation": operation, **fields}

    other = "Debian" if args.distribution != "Debian" else "Ubuntu-24.04"
    project = {"id": "arc.project.smoke", "distribution": other, "kind": "arc", "path": "/home/test/spaced project"}
    cases = [
        ("hello", request("hello"), None),
        ("incompatible version", request("version", protocolVersion=999), "unsupportedVersion"),
        ("malformed envelope", {"credential": "must-not-be-echoed"}, "invalidRequest"),
        ("unknown action", request("start", "project.teardown"), "unsupportedOperation"),
        ("wrong distribution", request("cross", "project.status", project=project), "wrongDistribution"),
        ("missing reference", request("missing", "project.status"), "missingProject"),
        ("invalid Linux path", request("unc", "project.status", project={**project, "distribution": args.distribution, "path": "C:\\project"}), "invalidProject"),
        ("invalid request ID", request("bad\n"), "invalidRequestID"),
        ("oversized frame", b"x" * (1_048_576 + 1), "frameTooLarge"),
        ("recovery after oversized frame", request("recovered"), None),
        ("final frame without newline", request("eof"), None),
    ]
    payload = b"\n".join(value if isinstance(value, bytes) else json.dumps(value).encode() for _, value, _ in cases)
    completed = subprocess.run(command, input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    if completed.returncode != 0:
        raise AssertionError(f"worker exited {completed.returncode}; diagnostic bytes={len(completed.stderr)}")
    if b"must-not-be-echoed" in completed.stdout or b"must-not-be-echoed" in completed.stderr:
        raise AssertionError("request data was echoed")
    responses = [json.loads(line) for line in completed.stdout.splitlines()]
    if len(responses) != len(cases):
        raise AssertionError(f"expected {len(cases)} JSON frames, got {len(responses)}")
    checks = []
    remaining = list(responses)
    for label, value, code in cases:
        expected_id = value.get("id") if isinstance(value, dict) and code not in ("invalidRequest", "invalidRequestID") else None
        response = next(item for item in remaining if item.get("id") == expected_id and item.get("error", {}).get("code") == code)
        remaining.remove(response)
        assert response["protocolVersion"] == 1, label
        assert response["distribution"] == args.distribution, label
        assert response.get("error", {}).get("code") == code, label
        assert response.get("id") == expected_id, label
        if code is None:
            assert response["capabilities"] == ["hello", "ddev.list", "project.status", "project.logs", "project.preflight", "project.start", "project.stop", "project.restart", "cancel", "remote.snapshot", "remote.verify", "remote.markRead", "remote.markRest"], label
        checks.append({"check": label, "passed": True})
    report = {"timeUTC": datetime.now(timezone.utc).isoformat(), "distribution": args.distribution,
              "passed": len(checks), "failed": 0, "workerExitCode": completed.returncode,
              "diagnosticBytes": len(completed.stderr), "checks": checks}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Worker transport: {len(checks)} passed, 0 failed; EOF exit {completed.returncode}.")


if __name__ == "__main__":
    main()
