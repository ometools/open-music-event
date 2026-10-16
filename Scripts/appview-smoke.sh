#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 BASE_URL [EXPECTED_CLIENT_ID]" >&2
}

fail() {
  echo "AppView smoke check failed: $*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || {
  usage
  exit 2
}

BASE_URL="${1%/}"
EXPECTED_CLIENT_ID="${2:-$BASE_URL/.well-known/oauth-client-metadata.json}"
CURL_BIN="${CURL_BIN:-curl}"

command -v "$CURL_BIN" >/dev/null 2>&1 || fail "curl is unavailable: $CURL_BIN"

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ome-appview-smoke.XXXXXX")"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

check_response() {
  local name="$1"
  local path="$2"
  local expected_content_type="$3"
  local body="$SMOKE_ROOT/$name.body"
  local headers="$SMOKE_ROOT/$name.headers"
  local expected_body_marker
  local status
  local content_type

  if ! status="$(
    "$CURL_BIN" \
      --silent \
      --show-error \
      --max-time 30 \
      --dump-header "$headers" \
      --output "$body" \
      --write-out '%{http_code}' \
      "$BASE_URL$path"
  )"; then
    echo "FAIL $path could not be fetched" >&2
    return 1
  fi

  if [[ "$status" != "200" ]]; then
    echo "FAIL $path returned HTTP $status" >&2
    return 1
  fi

  content_type="$(
    tr -d '\r' < "$headers" \
      | awk -F ': *' 'tolower($1) == "content-type" { value = $2 } END { print value }'
  )"
  if [[ "$content_type" != "$expected_content_type"* ]]; then
    echo "FAIL $path returned Content-Type '$content_type'; expected '$expected_content_type'" >&2
    return 1
  fi

  for expected_body_marker in "${@:4}"; do
    if ! grep -Fq "$expected_body_marker" "$body"; then
      echo "FAIL $path did not contain expected content: $expected_body_marker" >&2
      return 1
    fi
  done

  echo "PASS $path ($content_type)"
}

FAILED_CHECKS=0

run_check() {
  if ! check_response "$@"; then
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
}

run_check health "/healthz" "text/plain" "ok"
run_check readiness "/readyz" "text/plain" "ready"
run_check home "/" "text/html" "<title>Open Music Event</title>"
run_check stylesheet "/styles.css" "text/css" ":root"
run_check \
  oauth-client-metadata \
  "/.well-known/oauth-client-metadata.json" \
  "application/json" \
  "\"client_id\"" \
  "$EXPECTED_CLIENT_ID"

[[ "$FAILED_CHECKS" == "0" ]] \
  || fail "$FAILED_CHECKS public route check(s) failed"
