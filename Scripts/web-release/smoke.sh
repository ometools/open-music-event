#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 BASE_URL" >&2
}

fail() {
  echo "AppView smoke check failed: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || {
  usage
  exit 2
}

BASE_URL="${1%/}"
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
run_check home "/" "text/html" 'id="event-explorer"' 'id="searchForm"' 'value="events.openmusic.event"' 'value="community.lexicon.calendar.event"'
run_check globe-script "/assets/app.js" "text/javascript" "browseEventSummaries"
run_check globe-map-script "/assets/maplibre-gl-5.7.1.js" "text/javascript" "maplibregl"
run_check globe-map-style "/assets/maplibre-gl-5.7.1.css" "text/css" ".maplibregl-map"
run_check catalog "/xrpc/app.openmusicevent.calendar.browseEventSummaries?limit=1&catalogs=events.openmusic.event&catalogs=community.lexicon.calendar.event" "application/json" '"events"' 
run_check stylesheet "/styles.css" "text/css" ":root"

[[ "$FAILED_CHECKS" == "0" ]] \
  || fail "$FAILED_CHECKS public route check(s) failed"
