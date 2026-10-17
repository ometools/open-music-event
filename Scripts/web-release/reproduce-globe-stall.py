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
import gzip
import hashlib
import json
import os
import re
from pathlib import Path
import signal
import socket
import sqlite3
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
    parser.add_argument("--revision", help="Require this packaged release identity; omit only for a debug build")
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--zoom", type=int, default=6, choices=range(0, 19))
    parser.add_argument("--rounds", type=int, default=20)
    parser.add_argument("--request-timeout", type=float, default=5)
    parser.add_argument("--stress", action="store_true", help="Also exercise warm tiles, gzip, ETags, mixed browse traffic and abandoned clients")
    parser.add_argument("--browser-tiles", action="store_true", help="Also run the served JavaScript tile loader over real HTTP; requires Node 20+")
    parser.add_argument("--database-fixture", type=Path, help="Copy a synthetic fixture into this run; never write the source")
    parser.add_argument("--require-online-cpus", type=int, help="Fail rather than claim the requested CPU condition was tested")
    args = parser.parse_args()
    if not 2 <= args.workers <= 64 or not 1 <= args.rounds <= 256:
        parser.error("workers must be 2...64 and rounds must be 1...256")
    if not 0 < args.request_timeout <= 30:
        parser.error("request-timeout must be positive and at most 30 seconds")
    if args.require_online_cpus is not None and os.cpu_count() != args.require_online_cpus:
        parser.error(f"expected {args.require_online_cpus} online CPUs, found {os.cpu_count()}")
    test_started = time.monotonic()
    args.output.mkdir(parents=True, exist_ok=False)
    if args.database_fixture:
        with sqlite3.connect(args.database_fixture.resolve().as_uri() + "?mode=ro", uri=True) as source:
            with sqlite3.connect(args.output / "fixture.sqlite") as destination:
                source.backup(destination)
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
              "zoom": args.zoom, "rounds": [], "result": "incomplete", "onlineCPUs": os.cpu_count(),
              "affinityCPUs": len(os.sched_getaffinity(0))}

    def fixture_counts():
        path = (args.output / "fixture.sqlite").resolve().as_uri() + "?mode=ro"
        with sqlite3.connect(path, uri=True) as database:
            database.execute("PRAGMA query_only=ON")
            return {name: database.execute(query).fetchone()[0] for name, query in {
                "rawRecords": "SELECT COUNT(*) FROM appViewIndexedRecords",
                "canonicalEvents": 'SELECT COUNT(*) FROM "events.openmusic.event"',
                "browseEvents": "SELECT COUNT(*) FROM calendarEventBrowseProjections",
            }.items()}

    if args.database_fixture:
        report["fixtureBeforeStartup"] = fixture_counts()

    def fetch(path, gate=None, headers=None):
        if gate:
            gate.wait(timeout=10)
        started = time.monotonic()
        result = {"path": path}
        try:
            with urllib.request.urlopen(urllib.request.Request(origin + path, headers=headers or {}), timeout=args.request_timeout) as response:
                body = response.read()
                result.update(status=response.status, bytes=len(body))
                if path.startswith("/map/events/"):
                    encoded = response.headers.get("Content-Encoding") == "gzip"
                    data = gzip.decompress(body) if encoded else body
                    expected = '"' + hashlib.sha256(data).hexdigest() + ("-gzip" if encoded else "") + '"'
                    features = re.search(r'features;desc="(\d+)"', response.headers.get("Server-Timing", ""))
                    result.update(features=int(features[1]) if features else None,
                                  etag=response.headers.get("ETag"), gzip=encoded,
                                  validTile=bool(data) and response.headers.get("Content-Type") == "application/vnd.mapbox-vector-tile" and response.headers.get("ETag") == expected)
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
        side = 1 << args.zoom
        x, y = index % side, (index // side) % side
        if args.stress:
            x, y = (x * 37) % side, (y * 17 + side // 2) % side
        return (f"/map/events/{args.zoom}/{x}/{y}.mvt"
                "?catalogs=events.openmusic.event"
                "&catalogs=community.lexicon.calendar.event&dates=all")

    with (args.output / "server.log").open("wb") as log:
        server = subprocess.Popen([str(args.executable.resolve())], env=environment,
                                  stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        report["pid"] = server.pid
        previous_termination = signal.getsignal(signal.SIGTERM)

        def terminate_test(signum, _frame):
            # An outer CI deadline must also reap this harness's private child,
            # including the old deadlock that ignores graceful shutdown.
            report["result"] = "interrupted"
            if server.poll() is None:
                os.killpg(server.pid, signal.SIGKILL)
            raise SystemExit(128 + signum)

        signal.signal(signal.SIGTERM, terminate_test)
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

            if args.database_fixture:
                report["fixtureAfterStartup"] = fixture_counts()
                if report["fixtureAfterStartup"] != report["fixtureBeforeStartup"] or report["fixtureAfterStartup"]["browseEvents"] == 0:
                    report["result"] = "fixture_not_preserved"
                    return 1

            if args.revision:
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
                # Probe health while the tile burst is active, as well as after.
                probes = ["/healthz", "/readyz"]
                if args.stress:
                    probes += ["/", "/xrpc/app.openmusicevent.calendar.browseEventSummaries?catalogs=community.lexicon.calendar.event&dates=all",
                               "/xrpc/app.openmusicevent.calendar.getPublishers",
                               "/xrpc/app.openmusicevent.calendar.getSearchMapItems?uris=at%3A%2F%2Fdid%3Aplc%3Acapacity%2Fcommunity.lexicon.calendar.event%2F0000000001&zoom=2",
                               "/xrpc/app.openmusicevent.calendar.getEvent?uri=at%3A%2F%2Fdid%3Aplc%3Astress%2Fcommunity.lexicon.calendar.event%2Fmissing"]
                    if args.database_fixture:
                        probes.append("/xrpc/app.openmusicevent.calendar.getEvent?uri=at%3A%2F%2Fdid%3Aplc%3Acapacity%2Fcommunity.lexicon.calendar.event%2F0000000001")
                gate = threading.Barrier(args.workers + len(probes))
                with ThreadPoolExecutor(max_workers=args.workers + len(probes)) as pool:
                    futures = [pool.submit(fetch, tile(number * args.workers + (0 if args.stress and number % 3 == 1 else index)), gate,
                                           {"Accept-Encoding": "gzip"} if args.stress and index % 2 else {})
                               for index in range(args.workers)]
                    checks = [pool.submit(fetch, path, gate) for path in probes]
                    responses = [future.result() for future in futures]
                    concurrent = [future.result() for future in checks]
                health = fetch("/healthz")
                outcome = {"round": number + 1, "sharedColdTile": args.stress and number % 3 == 1, "tiles": responses, "health": health,
                           "concurrent": concurrent, "serverAlive": server.poll() is None}
                report["rounds"].append(outcome)
                emit({"round": number + 1, "statuses": {str(code): sum(r.get("status") == code for r in responses) for code in (200, 503)},
                      "health": health, "maxTileSeconds": max(r["seconds"] for r in responses)})
                if health.get("status") != 200 or health.get("body") != "ok":
                    report["result"] = "unresponsive_after_tiles" if server.poll() is None else "server_exited"
                    return 1
                if any(r.get("status") != (404 if r["path"].endswith("%2Fmissing") else 200) for r in concurrent):
                    report["result"] = "concurrent_route_failed"
                    return 1
                # Explicit, recoverable mapBusy is bounded backpressure.
                if any((r.get("status") == 200 and not r.get("validTile")) or
                       (r.get("status") != 200 and not (r.get("status") == 503 and r.get("retryAfter") == "1"))
                       for r in responses):
                    report["result"] = "tile_request_failed"
                    return 1
                if any(r.get("status") == 503 for r in responses):
                    time.sleep(1)  # Honor the server's explicit Retry-After.
                recovery = [fetch(r["path"]) for r in responses if r.get("status") == 503]
                outcome["recovery"] = recovery
                if any(r.get("status") != 200 or not r.get("validTile") for r in recovery):
                    report["result"] = "backpressure_did_not_recover"
                    return 1
                if args.stress:
                    # Revalidate the same tile with both wire representations.
                    warm = fetch(tile(number * args.workers), headers={"Accept-Encoding": "gzip"})
                    conditional = fetch(tile(number * args.workers), headers={"Accept-Encoding": "gzip", "If-None-Match": warm.get("etag", "")})
                    outcome.update(warm=warm, conditional=conditional)
                    if not warm.get("validTile") or conditional.get("status") != 304:
                        report["result"] = "cache_revalidation_failed"
                        return 1
                    # A closed client must not poison shared work for survivors.
                    for index in range(4):
                        with socket.create_connection(("127.0.0.1", port), timeout=args.request_timeout) as abandoned:
                            abandoned.sendall(("GET " + tile((number + 1) * args.workers + index) + " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n").encode())
                    outcome["afterAbandon"] = fetch(tile((number + 1) * args.workers))
                    if outcome["afterAbandon"].get("status") != 200:
                        report["result"] = "abandoned_client_poisoned_build"
                        return 1
                status_file = Path(f"/proc/{server.pid}/status")
                if status_file.exists():
                    outcome["resources"] = {line.split(":", 1)[0]: line.split(":", 1)[1].strip()
                                            for line in status_file.read_text().splitlines()
                                            if line.startswith(("VmRSS:", "Threads:"))}
            if args.database_fixture and not any(r.get("features", 0) for batch in report["rounds"] for r in batch["tiles"]):
                report["result"] = "fixture_served_no_features"
                return 1
            if args.database_fixture:
                report["fixtureAfterRequests"] = fixture_counts()
                if report["fixtureAfterRequests"] != report["fixtureBeforeStartup"]:
                    report["result"] = "fixture_not_preserved"
                    return 1
            if args.browser_tiles:
                client = subprocess.run(["node", str(Path(__file__).with_name("stress-event-tiles.mjs")), origin],
                                        capture_output=True, text=True, timeout=180)
                if client.returncode != 0:
                    report["browserTileError"] = client.stderr[-4000:]
                    report["result"] = "browser_tile_requests_failed"
                    return 1
                report["browserTiles"] = json.loads(client.stdout)
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
            signal.signal(signal.SIGTERM, previous_termination)
            if report["result"] == "passed" and server.returncode not in (0, -signal.SIGTERM):
                report["result"] = "shutdown_failed"
            samples = [r["seconds"] for batch in report["rounds"] for r in batch["tiles"]]
            samples.sort()
            if samples:
                report["tileLatencySeconds"] = {name: samples[min(len(samples) - 1, int(len(samples) * quantile))]
                                               for name, quantile in [("p50", .5), ("p95", .95), ("p99", .99), ("max", 1)]}
                report["tileRequests"] = len(samples)
            report["stress"] = args.stress
            report["elapsedSeconds"] = round(time.monotonic() - test_started, 3)
            (args.output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
            emit({"result": report["result"], "report": str(args.output / "result.json")})
            if report["result"] == "shutdown_failed":
                raise SystemExit(1)


if __name__ == "__main__":
    raise SystemExit(main())
