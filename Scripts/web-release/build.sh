#!/usr/bin/env bash
set -euo pipefail

mode="${1:-release}"
[[ "$mode" == pr || "$mode" == release ]] || { echo "Usage: $0 [pr|release]" >&2; exit 2; }
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "Build the web server on Linux x86-64, matching staging." >&2
  exit 1
}
: "${OME_RELEASE_REVISION:?Set the full source commit SHA}"
: "${OME_TOOLCHAIN_IMAGE:?Set the pinned toolchain image}"
: "${OME_CI_OWNER:?Set the host cache owner}"
jobs="${OME_SWIFT_JOBS:-1}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "OME_SWIFT_JOBS must be positive" >&2; exit 1; }
export OME_APPVIEW=1
export GIT_TERMINAL_PROMPT=0
output=/output
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  # The container runs as root; the CI user must own the persisted caches.
  chown -R "$OME_CI_OWNER" /src/.build /root/.cache/org.swift.swiftpm "$output"
}
trap cleanup EXIT
chown -R 0:0 /src/.build /root/.cache/org.swift.swiftpm
mkdir -p "$output"
cp Package.resolved "$output/Package.resolved.input"

phase() {
  local name="$1"
  shift
  echo "=== $name ==="
  python3 Scripts/web-release/resources.py
  local status=0
  /usr/bin/time -f "$name\t%e\t%M\t%x" -o "$output/phases.tsv" -a "$@" || status=$?
  tail -n 1 "$output/phases.tsv"
  python3 Scripts/web-release/resources.py
  return "$status"
}

# Reject machine-local inputs before resolution or compilation.
phase package-graph bash -c 'swift package dump-package > "$1"' -- "$output/package.json"
python3 - "$output/package.json" <<'PY'
import json, sys
dependencies = json.load(open(sys.argv[1]))["dependencies"]
paths = [entry["path"] for dependency in dependencies for entry in dependency.get("fileSystem", [])]
if paths:
    raise SystemExit("The web graph still uses local package paths; select published remote references before CI can build:\n" + "\n".join(paths))
PY

phase linux-tests swift test --scratch-path .build/web-tests --jobs "$jobs" --force-resolved-versions --no-parallel --xunit-output "$output/tests.xml"
# SwiftPM writes Swift Testing results separately from its XCTest report.
test_report="$output/tests-swift-testing.xml"
python3 - "$test_report" <<'PY'
import sys, xml.etree.ElementTree as ET
cases = list(ET.parse(sys.argv[1]).getroot().iter("testcase"))
if not cases or all(case.find("skipped") is not None for case in cases):
    raise SystemExit("The web test gate ran no tests")
if any(case.find("failure") is not None or case.find("error") is not None for case in cases):
    raise SystemExit("The web test report contains failures")
PY
cp "$test_report" "$output/tests.xml"
phase generated-lexicons swift run --scratch-path .build/web-tests --jobs "$jobs" --force-resolved-versions ome-export-lexicons --output Lexicons/Generated --check

if [[ "$mode" == pr ]]; then
  phase debug-server swift build --scratch-path .build/web-tests --jobs "$jobs" --force-resolved-versions --product OpenMusicEventAppView
  bin_dir="$(swift build --scratch-path .build/web-tests --jobs "$jobs" --force-resolved-versions --show-bin-path)"
  executable="$bin_dir/OpenMusicEventAppView"
else
  # Never run tests against the scratch directory that owns the release artifact.
  phase release-server swift build --scratch-path .build/web-release-build --jobs "$jobs" --force-resolved-versions -c release --product OpenMusicEventAppView
  bin_dir="$(swift build --scratch-path .build/web-release-build --jobs "$jobs" --force-resolved-versions -c release --show-bin-path)"
  phase package-release python3 Scripts/web-release/artifact.py package \
    --bin-dir "$bin_dir" --lockfile Package.resolved \
    --revision "$OME_RELEASE_REVISION" --toolchain-image "$OME_TOOLCHAIN_IMAGE" \
    --output "$output/release"
  executable="$output/release/appview/run"
fi
cmp Package.resolved "$output/Package.resolved.input"

# Both modes check a local server with a fresh database and no live ingestion.
OME_APPVIEW_HOST=127.0.0.1 OME_APPVIEW_PORT=18082 \
OME_APPVIEW_PUBLIC_HOST=stg.openmusicevent.app OME_OAUTH_CLIENT=production \
OME_APPVIEW_DATABASE_PATH="$output/smoke.sqlite" \
  "$executable" > "$output/smoke.log" 2>&1 &
server_pid=$!
for attempt in {1..60}; do
  if curl --silent --fail --max-time 1 http://127.0.0.1:18082/readyz >/dev/null; then break; fi
  kill -0 "$server_pid" || { cat "$output/smoke.log"; exit 1; }
  sleep 1
done
phase http-smoke bash Scripts/web-release/smoke.sh http://127.0.0.1:18082
# Exercise the real pooled HTTP path under overlapping tile and browse traffic.
# This child owns a separate disposable database and is always reaped by the harness.
stress_args=(--executable "$executable" --output "$output/request-stress" --workers 32 --rounds 16 --stress)
if [[ "$mode" == release ]]; then stress_args+=(--revision "$OME_RELEASE_REVISION"); fi
phase request-stress timeout --signal=TERM --kill-after=10s 180s \
  python3 Scripts/web-release/reproduce-globe-stall.py "${stress_args[@]}"
if [[ "$mode" == release ]]; then
  python3 Scripts/web-release/artifact.py verify "$output/release/appview" > "$output/verified-manifest.json"
  mkdir "$output/passed"
  cp "$output/release/appview.tar.gz" "$output/release/appview.tar.gz.sha256" \
    "$output/tests.xml" "$output/verified-manifest.json" "$output/passed/"
fi
