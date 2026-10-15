#!/usr/bin/env bash
set -euo pipefail

: "${TANGLED_SHA:?Tangled must supply the exact source revision}"
: "${GITHUB_TOKEN:?Private TCA read access is required}"
[[ "$TANGLED_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid source revision" >&2; exit 1; }
[[ "$GITHUB_TOKEN" != *[[:space:]]* ]] || { echo "Invalid GitHub credential" >&2; exit 1; }
secret_dir="$(mktemp -d)"
trap 'rm -rf "$secret_dir"' EXIT
umask 077
printf 'machine github.com\nlogin x-access-token\npassword %s\n' "$GITHUB_TOKEN" > "$secret_dir/netrc"
docker buildx build --platform linux/amd64 --target artifact \
  --secret "id=github_netrc,src=$secret_dir/netrc" \
  --build-arg "OME_RELEASE_REVISION=$TANGLED_SHA" \
  --output type=local,dest=.build/web-release \
  --file Scripts/web-release/Dockerfile .
