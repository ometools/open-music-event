#!/usr/bin/env python3
"""Exercise concurrent globe tiles against an isolated server with a fresh database.

Run in Linux with the desired CPU allocation. This starts only the supplied
executable, inherits no application credentials, and never targets a remote URL.
A nonzero exit means the HTTP responsiveness contract failed; it is not by itself
proof of a particular deadlock. Keep the JSON report and process diagnostics.

The observed reproduction requires two online CPUs. A container affinity limit
does not necessarily change the runtime's online CPU count. Always compare the
onlineCPUs field before treating a passing run as regression evidence.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import signal
import socket
import struct
import subprocess
import threading
import time
import urllib.error
import urllib.request


def blocked_stack_candidates(pid):
    """Symbolize executable addresses only; never persist stack data or payloads."""
    maps = []
    for line in Path(f"/proc/{pid}/maps").read_text().splitlines():
        fields = line.split(None, 5)
        start, end = (int(value, 16) for value in fields[0].split("-"))
        maps.append((start, end, fields[1], int(fields[2], 16),
                     fields[5] if len(fields) > 5 else ""))
    result = []
    fd = os.open(f"/proc/{pid}/mem", os.O_RDONLY)
    try:
        for task in sorted(Path(f"/proc/{pid}/task").iterdir()):
            if "futex" not in (task / "wchan").read_text():
                continue
            call = (task / "syscall").read_text().split()
            if len(call) < 3:
                continue
            pointer = int(call[-2], 16)
            stack = next(m for m in maps if m[0] <= pointer < m[1])
            data = os.pread(fd, min(8192, stack[1] - pointer), pointer)
            addresses = {}
            for offset in range(0, len(data) - 7, 8):
                value = struct.unpack_from("<Q", data, offset)[0]
                code = next((m for m in maps if "x" in m[2] and m[0] <= value < m[1]
                             and m[4].endswith("/OpenMusicEventAppView")), None)
                if code:
                    addresses.setdefault(value - code[0] + code[3], (offset, code[4]))
            if addresses:
                module = next(iter(addresses.values()))[1]
                symbols = subprocess.run(["addr2line", "-e", module, "-f", "-C"] +
                    [hex(address) for address in addresses], capture_output=True,
                    text=True, check=True, timeout=15).stdout.splitlines()
                result.append({"tid": int(task.name), "futex": call[1],
                    "candidates": [{"offset": offset, "symbol": symbols[2 * index],
                                    "source": symbols[2 * index + 1]}
                                   for index, (offset, _) in enumerate(addresses.values())]})
    finally:
        os.close(fd)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--rounds", type=int, default=20)
    parser.add_argument("--request-timeout", type=float, default=5)
    args = parser.parse_args()
    if not 2 <= args.workers <= 64 or not 1 <= args.rounds <= 64:
        parser.error("workers must be 2...64 and rounds must be 1...64")
    if not 0 < args.request_timeout <= 30:
        parser.error("request-timeout must be positive and at most 30 seconds")
    args.output.mkdir(parents=True, exist_ok=False)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    origin = f"http://127.0.0.1:{port}"
    environment = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(args.output.resolve()),
        "OME_APPVIEW_HOST": "127.0.0.1",
        "OME_APPVIEW_PORT": str(port),
        "OME_APPVIEW_PUBLIC_HOST": "stg.openmusicevent.app",
        "OME_OAUTH_CLIENT": "production",
        "OME_APPVIEW_DATABASE_PATH": str((args.output / "fixture.sqlite").resolve()),
    }
    report = {"expectedRevision": args.revision, "workers": args.workers,
              "rounds": [], "result": "incomplete", "onlineCPUs": os.cpu_count(),
              "affinityCPUs": len(os.sched_getaffinity(0))}

    def fetch(path, gate=None):
        if gate:
            gate.wait(timeout=10)
        started = time.monotonic()
        result = {"path": path}
        try:
            with urllib.request.urlopen(origin + path, timeout=args.request_timeout) as response:
                body = response.read()
                result.update(status=response.status, bytes=len(body))
                if path in ("/healthz", "/readyz"):
                    result["body"] = body.decode().strip()
                elif path == "/assets/release.json":
                    result["release"] = json.loads(body)
        except urllib.error.HTTPError as error:
            result.update(status=error.code, retryAfter=error.headers.get("Retry-After"))
            error.close()
        except (OSError, ValueError) as error:
            result["error"] = str(error)
        result["seconds"] = round(time.monotonic() - started, 3)
        return result

    def emit(value):
        print(json.dumps(value, sort_keys=True), flush=True)

    def tile(index):
        return (f"/map/events/6/{index % 64}/{index // 64}.mvt"
                "?catalogs=events.openmusic.event"
                "&catalogs=community.lexicon.calendar.event&dates=all")

    with (args.output / "server.log").open("wb") as log:
        server = subprocess.Popen([str(args.executable.resolve())], env=environment,
                                  stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        report["pid"] = server.pid
        try:
            deadline = time.monotonic() + 60
            while True:
                ready = fetch("/readyz")
                if ready.get("status") == 200 and ready.get("body") == "ready":
                    break
                if server.poll() is not None or time.monotonic() >= deadline:
                    report.update(result="startup_failed", readiness=ready)
                    return 1
                time.sleep(0.1)

            release = fetch("/assets/release.json")
            report["release"] = release
            if release.get("release", {}).get("sourceRevision") != args.revision:
                report["result"] = "revision_mismatch"
                return 1

            # The first page load works before the browser asks for many tiles.
            first = {"health": fetch("/healthz"), "home": fetch("/"), "tile": fetch(tile(4095))}
            report["initial"] = first
            emit({"initial": first})
            if any(value.get("status") != 200 for value in first.values()):
                report["result"] = "initial_request_failed"
                return 1

            for number in range(args.rounds):
                # A barrier launches distinct cold tiles together; no sleeps guess
                # the order of application tasks or hold a database connection.
                gate = threading.Barrier(args.workers)
                with ThreadPoolExecutor(max_workers=args.workers) as pool:
                    futures = [pool.submit(fetch, tile(number * args.workers + index), gate)
                               for index in range(args.workers)]
                    responses = [future.result() for future in futures]
                health = fetch("/healthz")
                outcome = {"round": number + 1, "tiles": responses, "health": health,
                           "serverAlive": server.poll() is None}
                report["rounds"].append(outcome)
                emit(outcome)
                if health.get("status") != 200 or health.get("body") != "ok":
                    report["result"] = "unresponsive_after_tiles" if server.poll() is None else "server_exited"
                    return 1
                # An explicit mapBusy response is permitted backpressure. A
                # timeout, other failure, or wrong response is not.
                if any(r.get("status") != 200 and
                       not (r.get("status") == 503 and r.get("retryAfter") == "1")
                       for r in responses):
                    report["result"] = "tile_request_failed"
                    return 1
            report["result"] = "passed"
            return 0
        finally:
            report["exitBeforeCleanup"] = server.poll()
            try:
                task_root = Path(f"/proc/{server.pid}/task")
                if task_root.exists():
                    report["threads"] = []
                    for task in sorted(task_root.iterdir()):
                        try:
                            report["threads"].append({"tid": int(task.name),
                                "name": (task / "comm").read_text().strip(),
                                "wait": (task / "wchan").read_text().strip()})
                        except FileNotFoundError:
                            pass
                    if report["result"] == "unresponsive_after_tiles":
                        report["stackCandidates"] = blocked_stack_candidates(server.pid)
            except (OSError, ValueError, StopIteration, subprocess.SubprocessError) as error:
                report["diagnosticError"] = str(error)
            if server.poll() is None:
                os.killpg(server.pid, signal.SIGTERM)
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(server.pid, signal.SIGKILL)
                    server.wait(timeout=5)
            report["exitAfterCleanup"] = server.returncode
            (args.output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
            emit({"result": report["result"], "report": str(args.output / "result.json")})


if __name__ == "__main__":
    raise SystemExit(main())
