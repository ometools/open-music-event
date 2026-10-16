#!/usr/bin/env python3
"""CI host installer: verify, back up SQLite, restart, and check the exact release."""
import argparse
from contextlib import closing
import fcntl
import json
import os
from pathlib import Path
import platform
import re
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

from artifact import digest, verify

BASE = Path("/srv/ome-appview")
UNIT_ROOT = Path("/etc/systemd/system")


def run(*command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def extract(archive, destination):
    with tarfile.open(archive, "r:gz") as source:
        members = source.getmembers()
        names = set()
        for member in members:
            path = Path(member.name)
            if (not member.isfile() or path.is_absolute() or ".." in path.parts
                    or member.name in names):
                raise ValueError("Release archive has an unsafe or duplicate entry")
            names.add(member.name)
        source.extractall(destination, members=members, filter="data")


def install(args):
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise ValueError("This artifact requires a Linux x86-64 host")
    operating_system = platform.freedesktop_os_release()
    if operating_system.get("ID") != "ubuntu" or operating_system.get("VERSION_ID") != "24.04":
        raise ValueError("This artifact requires Ubuntu 24.04")
    if os.geteuid() != 0:
        raise ValueError("Run the host installer through sudo")
    if not re.fullmatch(r"[0-9a-f]{64}", args.sha256):
        raise ValueError("Expected a SHA256 artifact digest")
    if not re.fullmatch(r"ome-appview[a-z0-9-]*\.service", args.service):
        raise ValueError("Expected an OME AppView service")
    if not args.database.is_absolute() or not args.database.is_file():
        raise ValueError("The existing database must be supplied; this installer never creates one")
    if digest(args.archive) != args.sha256:
        raise ValueError("Downloaded archive checksum mismatch")
    base = BASE
    with (base / ".ci-deploy.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        release = base / "releases" / args.sha256
        with tempfile.TemporaryDirectory(prefix=".ci-unpack-", dir=base / "releases") as temporary:
            incoming = Path(temporary)
            extract(args.archive, incoming)
            manifest = verify(incoming)
            if manifest["sourceRevision"] != args.revision or manifest["platform"] != "linux/amd64":
                raise ValueError("Artifact source revision or platform mismatch")
            if release.exists():
                if verify(release) != manifest:
                    raise ValueError("Installed release differs from the immutable candidate")
            else:
                shutil.copytree(incoming, release)
                release.chmod(0o755)
        bundle = next(p for p in release.glob("*.resources") if p.name.endswith("OpenMusicEventAppViewServer.resources"))
        identity = json.loads((bundle / "Site/assets/release.json").read_text())

        # Read only the running process's database setting. Never log its credentials.
        pid = run("systemctl", "show", args.service, "-p", "MainPID", "--value",
                  capture_output=True, text=True).stdout.strip()
        if pid == "0":
            raise ValueError("Expected an existing running service before deployment")
        environment = dict(item.split(b"=", 1) for item in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0") if b"=" in item)
        configured = environment.get(b"OME_APPVIEW_DATABASE_PATH", b"").decode()
        if not configured or Path(configured).resolve() != args.database.resolve():
            raise ValueError("Supplied backup path is not the running service's database")

        backup = base / "backups" / f"ci-{time.time_ns()}-{args.sha256[:12]}"
        backup.mkdir()
        dropin = UNIT_ROOT / (args.service + ".d") / "zzzz-ome-ci-release.conf"
        previous = dropin.read_bytes() if dropin.exists() else None
        # Unit files contain secret locations and may contain credentials; keep backups private.
        backup.chmod(0o700)
        (backup / "unit.before").write_bytes(run("systemctl", "cat", args.service, capture_output=True).stdout)
        run("systemctl", "stop", args.service)
        activated = False
        try:
            with closing(sqlite3.connect(args.database.as_uri() + "?mode=ro", uri=True)) as source:
                with closing(sqlite3.connect(backup / "appview.sqlite")) as target:
                    source.backup(target)
                    if target.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                        raise ValueError("SQLite backup did not pass quick_check")
            activated = True
            dropin.parent.mkdir(parents=True, exist_ok=True)
            dropin.write_text(
                "[Service]\nExecStart=\n"
                f"ExecStart={release}/run\nWorkingDirectory={release}\n"
                f"Environment=OME_APPVIEW_SITE_ROOT={bundle}/Site\n"
                f"Environment=OME_APPVIEW_WELL_KNOWN_ROOT={bundle}/WellKnown\n"
                f"Environment=LD_LIBRARY_PATH={release}/lib\n"
            )
            run("systemctl", "daemon-reload")
            run("systemctl", "start", args.service)
            for attempt in range(60):
                try:
                    with urllib.request.urlopen(args.base_url + "/readyz", timeout=5) as response:
                        if response.status == 200 and response.read().strip() == b"ready":
                            break
                except OSError:
                    pass
                time.sleep(1)
            run("bash", str(args.smoke_script), args.base_url)
            with urllib.request.urlopen(args.base_url + "/assets/release.json", timeout=10) as response:
                if json.load(response) != identity:
                    raise ValueError("Public host is not serving the candidate release")
            current_pid = run("systemctl", "show", args.service, "-p", "MainPID", "--value",
                              capture_output=True, text=True).stdout.strip()
            if Path(f"/proc/{current_pid}/exe").resolve() != release / "OpenMusicEventAppView":
                raise ValueError("The running executable does not match the candidate")
            verify(release)
            (backup / "result.json").write_text(json.dumps({
                "artifactSHA256": args.sha256, "sourceRevision": args.revision,
                "baseURL": args.base_url, "result": "passed"
            }) + "\n")
        except BaseException:
            if activated:
                # A new binary may have migrated the database. Never roll it back automatically.
                run("systemctl", "stop", args.service)
                print(f"Candidate failed; service stopped. Database and backup retained at {backup}", file=sys.stderr)
            else:
                run("systemctl", "start", args.service)
            if previous is None:
                dropin.unlink(missing_ok=True)
            else:
                dropin.write_bytes(previous)
            run("systemctl", "daemon-reload")
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--service", required=True)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--smoke-script", type=Path, required=True)
    args = parser.parse_args()
    try:
        install(args)
    except (OSError, ValueError, sqlite3.Error, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Deployment failed: {error}\n")


if __name__ == "__main__":
    main()
