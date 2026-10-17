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
import shlex
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

from artifact import digest, verify

BASE = Path("/srv/ome-appview")
UNIT_ROOT = Path("/etc/systemd/system")
STARTUP_TIMEOUT_SECONDS = 120
READINESS_TIMEOUT_SECONDS = 900
PROGRESS_INTERVAL_SECONDS = 30

MANAGED_ENVIRONMENT = {
    "OME_APPVIEW_SITE_ROOT", "OME_APPVIEW_WELL_KNOWN_ROOT", "LD_LIBRARY_PATH",
    "OME_APPVIEW_DATABASE_PATH",
}


def run(*command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def setting(service, name):
    return run("systemctl", "show", service, "-p", name, "--value",
               capture_output=True, text=True).stdout.strip()


def configured_environment(service):
    # EnvironmentFile and UnsetEnvironment take precedence over Environment.
    # Keep release/database selection in the unit, credentials in environment files.
    for entry in setting(service, "EnvironmentFiles").splitlines():
        match = re.fullmatch(r"(/.+) \(ignore_errors=(yes|no)\)", entry)
        if not match or any(c in match[1] for c in "*?[]\\"):
            raise ValueError("Cannot verify service EnvironmentFile path")
        path = Path(match[1])
        if not path.exists() and match[2] == "yes":
            continue
        contents = path.read_text().replace("\\\n", "")
        for key in MANAGED_ENVIRONMENT:
            if re.search(r"^\s*" + re.escape(key) + r"\s*=", contents, re.MULTILINE):
                raise ValueError(f"EnvironmentFile must not override {key}")
    for assignment in shlex.split(setting(service, "UnsetEnvironment")):
        if assignment.split("=", 1)[0] in MANAGED_ENVIRONMENT:
            raise ValueError("UnsetEnvironment must not remove release or database settings")
    return dict(item.split("=", 1) for item in shlex.split(setting(service, "Environment")))


def verify_selection(service, release, bundle, database):
    command = setting(service, "ExecStart")
    prefix = f"{{ path={release}/run ; argv[]={release}/run ; ignore_errors=no ; "
    if not command.startswith(prefix) or command.count("{ path=") != 1:
        raise ValueError("Effective ExecStart does not select the candidate; reconcile legacy drop-ins")
    if setting(service, "WorkingDirectory") != str(release):
        raise ValueError("Effective WorkingDirectory does not select the candidate")
    environment = configured_environment(service)
    expected = {
        "OME_APPVIEW_SITE_ROOT": str(bundle / "Site"),
        "OME_APPVIEW_WELL_KNOWN_ROOT": str(bundle / "WellKnown"),
        "LD_LIBRARY_PATH": str(release / "lib"),
    }
    for key, value in expected.items():
        if environment.get(key) != value:
            raise ValueError(f"Effective {key} does not select the candidate")
    configured = environment.get("OME_APPVIEW_DATABASE_PATH", "")
    if not configured or Path(configured).resolve() != database.resolve():
        raise ValueError("Supplied backup path is not the configured service database")


def verify_process(service, release, database):
    # Type=simple can briefly report the shell launcher before it execs the server.
    for attempt in range(50):
        pid = setting(service, "MainPID")
        if pid != "0" and Path(f"/proc/{pid}/exe").resolve() == release / "OpenMusicEventAppView":
            environment = dict(item.split(b"=", 1) for item in
                               Path(f"/proc/{pid}/environ").read_bytes().split(b"\0") if b"=" in item)
            configured = environment.get(b"OME_APPVIEW_DATABASE_PATH", b"").decode()
            if not configured or Path(configured).resolve() != database.resolve():
                raise ValueError("The running process is using a different database")
            return pid
        time.sleep(0.1)
    raise ValueError("The running executable does not match the candidate")


def require_process(service, pid):
    if setting(service, "MainPID") != pid or setting(service, "ActiveState") != "active":
        raise ValueError("Candidate process exited or restarted while verifying deployment")


def log_progress(database, phase, elapsed, timeout_seconds):
    checkpoints = None
    try:
        with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=1)) as source:
            source.execute("PRAGMA query_only=ON")
            checkpoints = dict(source.execute(
                "SELECT id, sequence FROM appViewCheckpoints ORDER BY id LIMIT 32"
            ).fetchall())
    except sqlite3.Error:
        # Older schemas or a busy database must not prevent bounded startup diagnostics.
        pass
    print(json.dumps({
        "phase": phase, "status": "waiting", "elapsedSeconds": round(elapsed, 1),
        "timeoutSeconds": timeout_seconds,
        "checkpointStatus": "available" if checkpoints is not None else "unavailable",
        "checkpoints": checkpoints,
    }), flush=True)


def wait_for_readiness(args, pid):
    for phase, path, expected, timeout_seconds in (
        ("startup", "/healthz", b"ok", STARTUP_TIMEOUT_SECONDS),
        ("catch-up", "/readyz", b"ready", READINESS_TIMEOUT_SECONDS),
    ):
        started = time.monotonic()
        deadline = started + timeout_seconds
        next_progress = started + PROGRESS_INTERVAL_SECONDS
        while True:
            require_process(args.service, pid)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError(f"Candidate {phase} deadline exceeded ({timeout_seconds} seconds)")
            passed = False
            try:
                with urllib.request.urlopen(args.base_url + path, timeout=min(5, remaining)) as response:
                    passed = response.status == 200 and response.read(128).strip() == expected
            except urllib.error.HTTPError as error:
                error.close()
            except OSError:
                pass
            # A response from a process that died or restarted cannot accept the candidate.
            require_process(args.service, pid)
            now = time.monotonic()
            if now >= deadline:
                raise ValueError(f"Candidate {phase} deadline exceeded ({timeout_seconds} seconds)")
            if passed:
                print(json.dumps({
                    "phase": phase, "status": "passed", "elapsedSeconds": round(now - started, 1),
                    "timeoutSeconds": timeout_seconds,
                }), flush=True)
                break
            if now >= next_progress:
                log_progress(args.database, phase, now - started, timeout_seconds)
                next_progress = now + PROGRESS_INTERVAL_SECONDS
            time.sleep(min(1, max(0, deadline - time.monotonic())))


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

        state = setting(args.service, "ActiveState")
        if state not in ("active", "inactive", "failed"):
            raise ValueError("Service is transitioning; retry after it settles")
        pid = setting(args.service, "MainPID")
        was_running = state == "active" and pid != "0"
        if (pid != "0") != was_running:
            raise ValueError("Service state and process disagree")
        configured = configured_environment(args.service).get("OME_APPVIEW_DATABASE_PATH", "")
        if not configured or Path(configured).resolve() != args.database.resolve():
            raise ValueError("Supplied backup path is not the configured service database")
        if was_running:
            # Read only the database setting. Never log process credentials.
            environment = dict(item.split(b"=", 1) for item in
                               Path(f"/proc/{pid}/environ").read_bytes().split(b"\0") if b"=" in item)
            configured = environment.get(b"OME_APPVIEW_DATABASE_PATH", b"").decode()
            if not configured or Path(configured).resolve() != args.database.resolve():
                raise ValueError("Supplied backup path is not the running service's database")

        backup = base / "backups" / f"ci-{time.time_ns()}-{args.sha256[:12]}"
        backup.mkdir()
        dropin = UNIT_ROOT / (args.service + ".d") / "50-ome-ci-release.conf"
        previous = dropin.read_bytes() if dropin.exists() else None
        # Unit files contain secret locations and may contain credentials; keep backups private.
        backup.chmod(0o700)
        (backup / "unit.before").write_bytes(run("systemctl", "cat", args.service, capture_output=True).stdout)
        stopped = False
        activated = False
        try:
            dropin.parent.mkdir(parents=True, exist_ok=True)
            dropin.write_text(
                "[Service]\nExecStart=\n"
                f"ExecStart={release}/run\nWorkingDirectory={release}\n"
                f"Environment=OME_APPVIEW_SITE_ROOT={bundle}/Site\n"
                f"Environment=OME_APPVIEW_WELL_KNOWN_ROOT={bundle}/WellKnown\n"
                f"Environment=LD_LIBRARY_PATH={release}/lib\n"
            )
            run("systemctl", "daemon-reload")
            verify_selection(args.service, release, bundle, args.database)
            run("systemctl", "stop", args.service)
            stopped = True
            with closing(sqlite3.connect(args.database.as_uri() + "?mode=ro", uri=True)) as source:
                with closing(sqlite3.connect(backup / "appview.sqlite")) as target:
                    source.backup(target)
                    if target.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                        raise ValueError("SQLite backup did not pass quick_check")
            activated = True
            run("systemctl", "start", args.service)
            candidate_pid = verify_process(args.service, release, args.database)
            wait_for_readiness(args, candidate_pid)
            run("bash", str(args.smoke_script), args.base_url)
            with urllib.request.urlopen(args.base_url + "/assets/release.json", timeout=10) as response:
                if json.load(response) != identity:
                    raise ValueError("Public host is not serving the candidate release")
            require_process(args.service, candidate_pid)
            verify_process(args.service, release, args.database)
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
            if previous is None:
                dropin.unlink(missing_ok=True)
            else:
                dropin.write_bytes(previous)
            run("systemctl", "daemon-reload")
            if stopped and not activated and was_running:
                run("systemctl", "start", args.service)
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
