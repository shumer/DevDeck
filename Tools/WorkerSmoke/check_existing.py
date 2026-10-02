#!/usr/bin/env python3
"""Read existing project states through the production Swift worker. No lifecycle operations."""
import argparse
import json
import subprocess
import threading
from datetime import datetime, timezone
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--distribution", required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--ddev-list", action="store_true")
    parser.add_argument("--arc-path", action="append", default=[])
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("worker command required")

    def call(requests):
        payload = b"".join(json.dumps(request).encode() + b"\n" for request in requests)
        worker = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        deadline = threading.Timer(90, worker.kill)
        deadline.start()
        try:
            worker.stdin.write(payload)
            worker.stdin.flush()
            responses = [json.loads(worker.stdout.readline()) for _ in requests]
            worker.stdin.close()
            worker.wait(timeout=5)
            assert worker.returncode == 0, f"worker exit {worker.returncode}"
        finally:
            deadline.cancel()
            if worker.poll() is None:
                worker.kill()
                worker.wait(timeout=5)
        responses.sort(key=lambda response: [request["id"] for request in requests].index(response["id"]))
        assert len(responses) == len(requests), "unexpected response count"
        for request, response in zip(requests, responses):
            assert response["protocolVersion"] == 1 and response["distribution"] == args.distribution
            assert response["id"] == request["id"]
            assert not response.get("error"), f"request failed: {response.get('error', {}).get('code')}"
        return responses

    hello = call([{"protocolVersion": 1, "id": "hello", "operation": "hello"}])[0]
    projects = []
    if args.ddev_list:
        inventory = call([{"protocolVersion": 1, "id": "inventory", "operation": "ddev.list"}])[0]
        projects.extend({"id": f"probe.ddev.{entry['name']}", "distribution": args.distribution,
                         "kind": "ddev", "path": entry["path"]} for entry in inventory["projects"])
    projects.extend({"id": f"probe.arc.{index}", "distribution": args.distribution, "kind": "arc", "path": path}
                    for index, path in enumerate(args.arc_path))
    requests = [{"protocolVersion": 1, "id": f"status-{index}", "operation": "project.status", "project": project}
                for index, project in enumerate(projects)]
    statuses = call(requests) if requests else []
    report = {"timeUTC": datetime.now(timezone.utc).isoformat(), "distribution": args.distribution,
              "readOnly": True, "capabilities": hello["capabilities"],
              "projects": [{"reference": project, "status": response["status"]}
                           for project, response in zip(projects, statuses)]}
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Swift worker: {len(projects)} existing projects read in {args.distribution}; no lifecycle commands.")
    for project, response in zip(projects, statuses):
        print(f"  {project['id']}: {response['status']['state']}")


if __name__ == "__main__":
    main()
