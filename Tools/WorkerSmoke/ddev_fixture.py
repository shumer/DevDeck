#!/usr/bin/env python3
"""An opt-in real DDEV fixture. Own XDG config, no shared router/agent or existing project actions."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import uuid


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--cleanup", action="store_true")
    args = parser.parse_args()
    base = Path.home() / ".local/share/devdeck/qualification"
    if args.cleanup:
        fixture = json.loads(args.report.read_text())
        root = Path(fixture["root"]).resolve()
        if root.parent != base.resolve() or not root.name.startswith("ddev-"):
            raise RuntimeError("Fixture is outside the owned qualification directory")
        marker = json.loads((root / "fixture.json").read_text())
        if marker != fixture or fixture["name"] != "devdeck-" + root.name[5:]:
            raise RuntimeError("Fixture ownership marker does not match")
    else:
        suffix = uuid.uuid4().hex[:12]
        root = base / ("ddev-" + suffix)
        project = root / "project with spaces"
        (project / "public").mkdir(parents=True, exist_ok=False)
        xdg = root / "config"
        (xdg / "ddev").mkdir(parents=True)
        # XDG_CONFIG_HOME is supported by installed DDEV 1.24.10. No user's globals are rewritten.
        (xdg / "ddev/global_config.yaml").write_text(
            "omit_containers: [ddev-router, ddev-ssh-agent]\n"
            "instrumentation_opt_in: false\nwsl2_no_windows_hosts_mgt: true\n"
            "performance_mode: none\n", encoding="utf-8")
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        fixture = {"root": str(root), "path": str(project), "xdg": str(xdg),
                   "distribution": "Ubuntu-24.04", "name": "devdeck-" + suffix,
                   "marker": "devdeck-owned-" + suffix, "port": port}
        (project / "public/index.php").write_text('<?php echo "' + fixture["marker"] + '";', encoding="utf-8")
        (root / "fixture.json").write_text(json.dumps(fixture, indent=2), encoding="utf-8")
        args.report.write_text(json.dumps(fixture, indent=2), encoding="utf-8")
    environment = dict(os.environ, XDG_CONFIG_HOME=fixture["xdg"], CI="true", CAROOT=str(root / "certificates"))
    if args.cleanup:
        command = ["ddev", "delete", "--omit-snapshot", "--yes", fixture["name"]]
    else:
        command = ["ddev", "config", "--project-name=" + fixture["name"], "--project-type=php", "--docroot=public",
                   "--omit-containers=db,ddev-ssh-agent", "--host-webserver-port=" + str(fixture["port"])]
    completed = subprocess.run(command, cwd=fixture["path"], env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)
    if completed.returncode:
        raise RuntimeError("Owned DDEV fixture command failed, exit " + str(completed.returncode) + "; diagnostic bytes=" + str(len(completed.stderr)))
    print("Owned DDEV fixture " + ("deleted" if args.cleanup else "configured") + "; existing projects/globals untouched.")


if __name__ == "__main__":
    main()
