#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "Build the web release on Linux x86-64, matching staging." >&2
  exit 1
}
: "${OME_RELEASE_REVISION:?Set the full source commit SHA}"
: "${OME_TOOLCHAIN_IMAGE:?Set the pinned toolchain image}"
export OME_APPVIEW=1
export GIT_TERMINAL_PROMPT=0
output=/output
mkdir -p "$output"
cp Package.resolved "$output/Package.resolved.input"

# Reject machine-local inputs before resolution or compilation.
swift package dump-package > "$output/package.json"
python3 - "$output/package.json" <<'PY'
import json, sys
dependencies = json.load(open(sys.argv[1]))["dependencies"]
paths = [entry["path"] for dependency in dependencies for entry in dependency.get("fileSystem", [])]
if paths:
    raise SystemExit("Publish the web dependencies before CI can build:\n" + "\n".join(paths))
PY

swift test --force-resolved-versions --no-parallel --xunit-output "$output/tests.xml"
python3 - "$output/tests.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
cases = list(ET.parse(sys.argv[1]).getroot().iter("testcase"))
if not cases or all(case.find("skipped") is not None for case in cases):
    raise SystemExit("The web test gate ran no tests")
if any(case.find("failure") is not None or case.find("error") is not None for case in cases):
    raise SystemExit("The web test report contains failures")
PY
swift build --force-resolved-versions -c release --product OpenMusicEventAppView
cmp Package.resolved "$output/Package.resolved.input"
bin_dir="$(swift build --force-resolved-versions -c release --show-bin-path)"
python3 Scripts/web-release/artifact.py package \
  --bin-dir "$bin_dir" --lockfile Package.resolved \
  --revision "$OME_RELEASE_REVISION" --toolchain-image "$OME_TOOLCHAIN_IMAGE" \
  --output "$output/release"

# Smoke-test the packaged payload with an isolated database and no ingestion or providers.
OME_APPVIEW_HOST=127.0.0.1 OME_APPVIEW_PORT=18082 \
OME_APPVIEW_PUBLIC_HOST=stg.openmusicevent.app OME_OAUTH_CLIENT=production \
OME_APPVIEW_DATABASE_PATH="$output/smoke.sqlite" \
  "$output/release/appview/run" > "$output/smoke.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT
for attempt in {1..60}; do
  if curl --silent --fail --max-time 1 http://127.0.0.1:18082/readyz >/dev/null; then break; fi
  kill -0 "$server_pid" || { cat "$output/smoke.log"; exit 1; }
  sleep 1
done
bash Scripts/web-release/smoke.sh http://127.0.0.1:18082
python3 Scripts/web-release/artifact.py verify "$output/release/appview" > "$output/verified-manifest.json"
mkdir "$output/passed"
cp "$output/release/appview.tar.gz" "$output/release/appview.tar.gz.sha256" \
  "$output/tests.xml" "$output/verified-manifest.json" "$output/passed/"
