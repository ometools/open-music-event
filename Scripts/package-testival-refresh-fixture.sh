#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
initial_source="$repo_root/Sources/OpenMusicEventApp/Resources/UIAutomation/TestivalSource"
overrides="$repo_root/.maestro/fixtures/TestivalRefreshOverrides"
output="$repo_root/Sources/OpenMusicEventApp/Resources/UIAutomation/testival-refresh-b-gzip.fixture"
temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT

mkdir -p "$temporary_root/source"
cp -R "$initial_source/." "$temporary_root/source/"
cp -R "$overrides/." "$temporary_root/source/"

# Fixed timestamps and gzip metadata make the tracked server artifact reproducible. Its opaque
# resource extension prevents Android packaging from transparently expanding the gzip bytes.
find "$temporary_root/source" -exec touch -t 202608010000 {} +
COPYFILE_DISABLE=1 tar \
  --format ustar \
  --uid 0 \
  --gid 0 \
  --uname root \
  --gname root \
  -C "$temporary_root/source" \
  -cf "$temporary_root/testival-refresh-b.tar" \
  .
gzip -n -c "$temporary_root/testival-refresh-b.tar" > "$output"

printf 'sha256 (base64): '
openssl dgst -sha256 -binary "$output" | openssl base64 -A
printf '\n'
wc -c "$output"
