#!/usr/bin/env python3
"""Check frozen macOS surfaces and the active macOS package graph during migration."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--baseline", default="docs/migration/macos-baseline.json")
args = parser.parse_args()
baseline = json.loads((root / args.baseline).read_text())
errors = []
for name, expected in baseline["sha256"].items():
    path = root / name
    # Normalize Git line endings so Windows checkouts do not produce false regressions.
    contents = path.read_bytes().replace(b"\r\n", b"\n") if path.exists() else None
    if contents is not None and name == "Tests/DevDeckTests/ProjectTests.swift":
        # A Linux-only expectation may differ; the active Mac test must remain byte-for-byte intact.
        contents = re.sub(rb"^#if os\(macOS\)\n(.*?)^#else\n.*?^#endif\n", rb"\1", contents, flags=re.M | re.S)
    actual = hashlib.sha256(contents).hexdigest() if contents is not None else None
    if actual != expected:
        errors.append(name)
manifest = (root / "Package.swift").read_text()
if "#if os(macOS)\nlet package" in manifest:
    manifest = "let package" + manifest.split("#if os(macOS)\nlet package", 1)[1].split("\n#else", 1)[0]
else:
    manifest = "let package" + manifest.split("let package", 1)[1]
actual = hashlib.sha256(manifest.strip().encode()).hexdigest()
if actual != baseline["macOSManifestSHA256"]:
    errors.append("Package.swift active macOS graph")
if errors:
    print("Mac contract changed; review required:")
    print("\n".join(errors))
    sys.exit(1)
print("Mac contract unchanged: " + str(len(baseline["sha256"])) + " files and macOS package graph.")
