"""Read-only inventory of actual WSL projects; secret values and response bodies are omitted."""
import argparse
import concurrent.futures
import datetime
import json
import os
from pathlib import Path
import platform
import re
import shutil
import socket
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


def command(argv, cwd=None, env=None, timeout=30):
    try:
        result = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
        return {"exit": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"exit": -1, "stdout": "", "stderr": type(error).__name__}


def endpoint(url):
    result = {"url": url}
    host = urllib.parse.urlsplit(url).hostname
    try:
        result["addresses"] = sorted({row[4][0] for row in socket.getaddrinfo(host, None)})
    except OSError:
        result["dns"] = "failed"
    try:
        # Probes are local and should not silently follow a redirect to a hosted environment.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        with opener.open(urllib.request.Request(url, method="GET"), timeout=4) as response:
            result["status"] = response.status
    except urllib.error.HTTPError as error:
        result["status"] = error.code
    except urllib.error.URLError as error:
        if isinstance(error.reason, ssl.SSLCertVerificationError):
            result["error"] = "certificate_verification_failed"
        elif isinstance(error.reason, ConnectionRefusedError):
            result["error"] = "connection_refused"
        else:
            result["error"] = type(error.reason).__name__
    except (OSError, TimeoutError) as error:
        result["error"] = type(error).__name__
    return result


def docker_inventory():
    daemon = command(["docker", "info", "--format", "{{json .ID}}"])
    ids = command(["docker", "ps", "--all", "--quiet"])
    rows = command(["docker", "inspect", *ids["stdout"].split()]) if ids["stdout"].strip() else {"exit": 0, "stdout": "[]"}
    containers = []
    if rows["exit"] == 0:
        for row in json.loads(rows["stdout"]):
            labels = row["Config"].get("Labels") or {}
            containers.append({"name": row["Name"].lstrip("/"), "state": row["State"]["Status"],
                "image": row["Config"]["Image"], "imageId": row["Image"],
                "composeDirectory": labels.get("com.docker.compose.project.working_dir", ""),
                "composeProject": labels.get("com.docker.compose.project", ""),
                "ddevProject": labels.get("com.ddev.site-name", ""),
                "ports": row.get("NetworkSettings", {}).get("Ports", {})})
    return {"ready": daemon["exit"] == 0, "daemonId": daemon["stdout"].strip(), "containers": containers}


def small_config(path):
    result = {}
    if not path.exists():
        return result
    database = False
    for line in path.read_text(errors="replace").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[0].isspace():
            database = line.strip().startswith("database:")
        match = re.match(r"\s*([a-z_]+):\s*(.*?)\s*(?:#.*)?$", line)
        if not match:
            continue
        key, value = match.groups()
        if database and line[0].isspace() and key in ("type", "version"):
            result["database_" + key] = value.strip("\"'")
        elif not line[0].isspace() and key in ("name", "type", "php_version", "router_http_port", "router_https_port"):
            result[key] = value.strip("\"'")
    return result


def ubuntu():
    listing = command(["ddev", "list", "-j"])
    envelopes = []
    for line in listing["stdout"].splitlines():
        try:
            envelopes.append(json.loads(line))
        except ValueError:
            pass
    raw = next((envelope.get("raw", []) for envelope in envelopes if "raw" in envelope), [])
    docker = docker_inventory()
    projects = []
    for entry in raw:
        folder = Path(entry["approot"])
        related = [row for row in docker["containers"] if row["composeDirectory"] == str(folder) or
                   row["composeDirectory"].startswith(str(folder) + "/")]
        urls = [entry[key] for key in ("httpurl", "httpsurl") if entry.get(key)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            probes = list(pool.map(endpoint, urls))
        projects.append({"name": entry["name"], "folder": str(folder), "folderExists": folder.is_dir(),
                         "config": small_config(folder / ".ddev/config.yaml"),
                         "ddevStatus": entry.get("status"), "urls": urls, "linuxEndpoints": probes,
                         "containers": [{k: v for k, v in row.items() if k != "imageId"} for row in related]})
    router = next((row for row in docker["containers"] if row["name"] == "ddev-router"), None)
    version = command(["ddev", "version", "-j"])
    try:
        ddev_version = json.loads(version["stdout"]).get("raw", {}).get("DDEV version")
    except (ValueError, AttributeError):
        ddev_version = None
    return {"architecture": platform.machine(), "dockerReady": docker["ready"],
            "daemonId": docker["daemonId"], "ddevListExit": listing["exit"], "ddevVersion": ddev_version,
            "routerState": router["state"] if router else "absent", "projects": projects}


def arc_candidates(root):
    found = []
    for base, dirs, files in os.walk(root):
        depth = len(Path(base).relative_to(root).parts)
        dirs[:] = [name for name in dirs if not name.startswith(".") and name not in
                   ("node_modules", "dist", "build", "vendor", "coverage") and depth < 3]
        if "package.json" not in files:
            continue
        path = Path(base)
        try:
            package = json.loads((path / "package.json").read_text())
        except (OSError, ValueError):
            continue
        dependencies = {**package.get("dependencies", {}), **package.get("devDependencies", {})}
        fusion = {key: value for key, value in dependencies.items() if "fusion" in key.lower() and "cli" in key.lower()}
        if fusion or (path / ".fusion/docker-compose.yml").exists() or (path / "node_modules/.bin/fusion").exists():
            found.append((path, fusion))
    return found


def debian():
    environment = os.environ.copy()
    baseline = {"node": shutil.which("node"), "npx": shutil.which("npx")}
    probe = command(["zsh", "-ilc", "printf '__DEVDECK_PATH__%s\\n' \"$PATH\""])
    for line in probe["stdout"].splitlines():
        if line.startswith("__DEVDECK_PATH__"):
            environment["PATH"] = line[len("__DEVDECK_PATH__"):]
    node = shutil.which("node", path=environment["PATH"])
    npx = shutil.which("npx", path=environment["PATH"])
    node_version = command([node, "--version"])["stdout"].strip() if node else None
    docker = docker_inventory()
    projects = []
    root = Path.home() / "Project"
    for folder, fusion in arc_candidates(root):
        values = {}
        env_path = folder / ".env"
        if env_path.exists():
            for line in env_path.read_text(errors="replace").splitlines():
                match = re.match(r"(?:export\s+)?(PORT|FUSION_RELEASE)\s*=\s*([\"']?)([a-zA-Z0-9_.-]+)\2\s*(?:#.*)?$", line)
                if match:
                    values[match[1]] = match[3]
        port = int(values.get("PORT", "80")) if values.get("PORT", "80").isdigit() else 80
        binary = folder / "node_modules/.bin/fusion"
        installed = {}
        if binary.exists():
            target = binary.resolve()
            for ancestor in list(target.parents)[:4]:
                manifest = ancestor / "package.json"
                if manifest.exists():
                    data = json.loads(manifest.read_text())
                    if data.get("bin"):
                        installed = {"name": data.get("name"), "version": data.get("version")}
                        break
        cli = command([node, str(binary), "--version"], cwd=folder, env=environment, timeout=15) if node and binary.exists() else None
        cli_version = re.search(r"\b\d+\.\d+\.\d+\b", cli["stdout"]) if cli else None
        help_probe = command([node, str(binary), "help"], cwd=folder, env=environment, timeout=15) if node and binary.exists() else None
        command_names = [name for name in ("daemon", "start", "stop", "restart", "down", "rebuild")
                         if help_probe and re.search(r"\b" + name + r"\b", help_probe["stdout"])]
        cli_error = None
        if cli and cli["exit"]:
            text = cli["stdout"] + cli["stderr"]
            # Report stable error categories only, not arbitrary output from project tooling.
            if "ERR_REQUIRE_ASYNC_MODULE" in text:
                cli_error = "ERR_REQUIRE_ASYNC_MODULE"
            elif "ERR_REQUIRE_ESM" in text:
                cli_error = "ERR_REQUIRE_ESM"
            elif "Cannot find module" in text or "MODULE_NOT_FOUND" in text:
                cli_error = "MODULE_NOT_FOUND"
            elif "unknown option" in text.lower():
                cli_error = "unsupported_version_option"
            elif "SyntaxError" in text:
                cli_error = "SyntaxError"
            else:
                cli_error = "unclassified_failure"
        compose = folder / ".fusion/docker-compose.yml"
        compose_info = {"exists": compose.exists()}
        if compose.exists():
            config = command(["docker", "compose", "--file", str(compose), "config", "--format", "json"], cwd=folder)
            compose_info["valid"] = config["exit"] == 0
            if config["exit"] == 0:
                content = json.loads(config["stdout"])
                compose_info["services"] = [{"name": key, "image": service.get("image"),
                    "platform": service.get("platform"), "ports": service.get("ports", [])}
                    for key, service in content.get("services", {}).items()]
                images = sorted({item["image"] for item in compose_info["services"] if item["image"]})
                image_info = []
                for image in images:
                    result = command(["docker", "image", "inspect", image, "--format", "{{json .Architecture}}"])
                    image_info.append({"image": image, "cached": result["exit"] == 0,
                                       "architecture": json.loads(result["stdout"]) if result["exit"] == 0 else None})
                compose_info["images"] = image_info
        related = [row for row in docker["containers"] if row["composeDirectory"] == str(folder) or
                   row["composeDirectory"].startswith(str(folder) + "/")]
        conflicts = []
        for service in compose_info.get("services", []):
            for published in service.get("ports", []):
                for row in docker["containers"]:
                    if row["state"] != "running" or row in related:
                        continue
                    for target, mappings in row["ports"].items():
                        for mapping in mappings or []:
                            if mapping["HostPort"] == str(published.get("published")) and target.endswith(
                                    "/" + published.get("protocol", "tcp")):
                                conflict = {"service": service["name"], "port": mapping["HostPort"],
                                            "owner": row["name"]}
                                if conflict not in conflicts:
                                    conflicts.append(conflict)
        url = "http://127.0.0.1:" + str(port) + "/release"
        projects.append({"name": folder.name, "folder": str(folder), "fusionDependency": fusion,
            "localFusionBinary": binary.exists(), "installedCLI": installed, "cliVersionExit": cli["exit"] if cli else None,
            "cliVersion": cli_version.group() if cli_version else None, "cliError": cli_error, "port": port,
            "cliHelpExit": help_probe["exit"] if help_probe else None, "advertisedCommands": command_names,
            "configuredRelease": values.get("FUSION_RELEASE"), "compose": compose_info,
            "publishedPortConflicts": conflicts,
            "containers": [{k: v for k, v in row.items() if k != "imageId"} for row in related],
            "urls": [url], "linuxEndpoints": [endpoint(url)]})
    return {"architecture": platform.machine(), "dockerReady": docker["ready"], "daemonId": docker["daemonId"],
            "baselineTools": baseline, "loginShellTools": {"node": node, "npx": npx, "nodeVersion": node_version},
            "projects": projects}


def windows_main(args):
    source = Path(__file__).read_text(encoding="utf-8")
    def inspect(distribution, kind):
        process = subprocess.run(["wsl.exe", "--distribution", distribution, "--cd", "/home/ashumenko",
                                  "--exec", "python3", "-", "--linux-kind", kind], input=source,
                                 capture_output=True, text=True, encoding="utf-8", timeout=150,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        if process.returncode:
            raise RuntimeError(distribution + " inventory failed with exit " + str(process.returncode))
        result = json.loads(process.stdout)
        urls = sorted({url for project in result["projects"] for url in project["urls"]})
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            result["windowsEndpoints"] = list(pool.map(endpoint, urls))
        return result
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        jobs = {"Ubuntu-24.04": pool.submit(inspect, "Ubuntu-24.04", "ddev"),
                "Debian": pool.submit(inspect, "Debian", "arc")}
        report = {"date": datetime.date.today().isoformat(), "readOnly": True,
                  "distributions": {name: job.result() for name, job in jobs.items()}}
    report["sharedDockerDaemon"] = bool(report["distributions"]["Ubuntu-24.04"]["daemonId"]) and (
        report["distributions"]["Ubuntu-24.04"]["daemonId"] == report["distributions"]["Debian"]["daemonId"])
    Path(args.report).write_text(json.dumps(report, indent=2), encoding="utf-8")
    for name, result in report["distributions"].items():
        print(name + ": " + str(len(result["projects"])) + " projects; Docker ready=" + str(result["dockerReady"]))
        for project in result["projects"]:
            description = project.get("ddevStatus") or ("Fusion CLI " + str(project["installedCLI"].get("version")) +
                          ", help exit=" + str(project.get("cliHelpExit")))
            print("  " + project["name"] + ": " + description)
    print("Shared Docker daemon=" + str(report["sharedDockerDaemon"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--linux-kind", choices=("ddev", "arc"))
    parser.add_argument("--report", default=".local_docs/windows-existing-projects.json")
    args = parser.parse_args()
    if args.linux_kind:
        print(json.dumps(ubuntu() if args.linux_kind == "ddev" else debian()))
    else:
        windows_main(args)
