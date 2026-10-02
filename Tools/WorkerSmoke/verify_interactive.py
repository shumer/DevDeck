#!/usr/bin/env python3
"""Verify that a response arrives while worker stdin remains open (Linux/WSL)."""
import argparse
import json
import select
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--distribution", required=True)
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ["--"] else args.command
worker = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    for number in range(3):
        request = {"protocolVersion": 1, "id": str(number), "operation": "hello"}
        worker.stdin.write(json.dumps(request).encode() + b"\n")
        worker.stdin.flush()
        readable, _, _ = select.select([worker.stdout], [], [], 3)
        assert readable, "worker did not respond while stdin remained open"
        response = json.loads(worker.stdout.readline())
        assert response["id"] == str(number) and response["distribution"] == args.distribution
    print("Interactive worker: 3 responses arrived before EOF.")
finally:
    worker.stdin.close()
    try:
        worker.wait(timeout=5)
    except subprocess.TimeoutExpired:
        worker.kill()
        worker.wait(timeout=5)
