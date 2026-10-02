#!/usr/bin/env python3
"""Detect source/spec drift; this inventory is evidence of scope, not behavioral qualification."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "docs/macos-functional-spec.md"
INVENTORY = ROOT / "docs/macos-spec-inventory.json"


def inventory():
    paths = [p for p in (ROOT / "Sources").rglob("*") if p.is_file()
             and p.parts[len(ROOT.parts) + 1] not in ("DevDeckWorker", "DevDeckWorkerProtocol", "WSLProcessSupport")]
    paths += [p for p in (ROOT / "Resources").rglob("*") if p.is_file()]
    paths += [ROOT / name for name in ("CLAUDE.md", "Package.swift", "build.sh", "run-tests.sh", "VERSION")]
    paths += [ROOT / "docs" / name for name in ("architecture.md", "development.md", "github-api.md")]
    paths += [p for p in (ROOT / "docs/adr").glob("*.md") if int(p.name[:4]) <= 22]
    result = []
    for path in sorted(set(paths)):
        raw = path.read_bytes()
        entry = {"path": path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}
        if path.suffix == ".swift":
            lines = raw.decode("utf-8").splitlines()
            entry["entryPoints"] = [{"line": i, "declaration": line.strip()} for i, line in enumerate(lines, 1)
                if re.search(r"\b(func|class|struct|enum|protocol)\s+\w+|\b(?:public\s+)?var\s+\w+\s*:", line)]
            entry["localizedControls"] = [{"line": i, "key": key} for i, line in enumerate(lines, 1)
                for key in re.findall(r'\bL[N]?\("([^"]+)"', line)]
        result.append(entry)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="Record a reviewed source baseline after updating the specification.")
    args = parser.parse_args()
    spec = SPEC.read_text()
    ids = re.findall(r"^\| ([A-Z]+-\d{2}) \|", spec, re.M)
    if not ids or len(ids) != len(set(ids)):
        raise SystemExit("Feature IDs are missing or duplicated.")
    for target, line in re.findall(r"\]\(\.\./([^)#]+)#L(\d+)\)", spec):
        path = ROOT / target
        if not path.is_file() or int(line) > len(path.read_text().splitlines()):
            raise SystemExit(f"Invalid source reference: {target}:{line}")
    current = {"schemaVersion": 1, "reviewedOn": "2026-10-01", "featureIDs": ids, "files": inventory(),
               "qualification": "Source inventory and acceptance contract only; native Mac/live external gates remain open."}
    if args.refresh:
        INVENTORY.write_text(json.dumps(current, ensure_ascii=False, indent=2) + "\n")
    else:
        previous = json.loads(INVENTORY.read_text())
        if previous["featureIDs"] != current["featureIDs"] or previous["files"] != current["files"]:
            raise SystemExit("Mac source/spec drift: review affected features and regenerate the inventory with --refresh.")
    print(f"Mac specification: {len(ids)} unique features, {len(current['files'])} source/resource/document files; references and baseline valid.")


if __name__ == "__main__":
    main()
