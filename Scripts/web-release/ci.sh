#!/usr/bin/env bash
set -euo pipefail

mode="${1:-release}"
[[ "$mode" == pr || "$mode" == release ]] || { echo "Usage: $0 [pr|release]" >&2; exit 2; }
: "${GITHUB_SHA:?GitHub must supply the exact source revision}"
: "${OME_DEPENDENCY_TOKEN:?Private TCA read access is required}"
[[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid source revision" >&2; exit 1; }
[[ "$OME_DEPENDENCY_TOKEN" != *[[:space:]]* ]] || { echo "Invalid GitHub credential" >&2; exit 1; }
jobs="${OME_SWIFT_JOBS:-1}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "OME_SWIFT_JOBS must be positive" >&2; exit 1; }
root="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$root"

# Keep local compiler state separate for each exact package graph and toolchain.
# Do not upload this cache: SwiftPM checkouts include the private TCA dependency.
compatibility="$(python3 - <<'PY'
import hashlib
from pathlib import Path
digest = hashlib.sha256(b"linux-amd64-appview-v1")
for name in ("Package.swift", "Package.resolved", "Scripts/web-release/Dockerfile"):
    digest.update(Path(name).read_bytes())
print(digest.hexdigest())
PY
)"
cache="$root/.cache/web-ci/$mode/$compatibility"
mkdir -p "$root/.build" "$cache/build" "$cache/swiftpm"
output="$(mktemp -d "$root/.build/web-$mode-run.XXXXXX")"
secret_dir="$(mktemp -d)"
container="ome-web-$mode-${GITHUB_SHA:0:12}-$$"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf "$secret_dir"
}
trap cleanup EXIT
umask 077
printf 'machine github.com\nlogin x-access-token\npassword %s\n' "$OME_DEPENDENCY_TOKEN" > "$secret_dir/netrc"

echo "Runner memory before toolchain preparation:"
python3 Scripts/web-release/resources.py
docker info --format 'Docker CPUs={{.NCPU}} MemoryBytes={{.MemTotal}}'
image="ome-web-toolchain:$compatibility"
docker buildx build --platform linux/amd64 --target toolchain --load \
  --progress plain --tag "$image" --file Scripts/web-release/Dockerfile .

echo "Running $mode checks with $jobs Swift job(s). Reports: $output"
# Only the dependency-read credential enters the build container. Source is
# read-only; compiler state and reports use separate writable mounts.
docker run --rm --name "$container" --platform linux/amd64 \
  --mount "type=bind,src=$root,dst=/src,readonly" \
  --mount "type=bind,src=$cache/build,dst=/src/.build" \
  --mount "type=bind,src=$cache/swiftpm,dst=/root/.cache/org.swift.swiftpm" \
  --mount "type=bind,src=$output,dst=/output" \
  --mount "type=bind,src=$secret_dir/netrc,dst=/root/.netrc,readonly" \
  --env "OME_RELEASE_REVISION=$GITHUB_SHA" --env "OME_SWIFT_JOBS=$jobs" \
  --env "OME_CI_OWNER=$(id -u):$(id -g)" \
  "$image" bash Scripts/web-release/build.sh "$mode"

destination="$root/.build/web-$mode"
mkdir -p "$destination"
if [[ "$mode" == release ]]; then
  cp "$output/passed/"* "$destination/"
else
  cp "$output/tests.xml" "$output/phases.tsv" "$output/smoke.log" "$destination/"
fi
