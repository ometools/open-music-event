#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOMEBREW_RUBY_BIN="/opt/homebrew/opt/ruby/bin"

if [[ -x "$HOMEBREW_RUBY_BIN/bundle" ]]; then
  export PATH="$HOMEBREW_RUBY_BIN:$PATH"
fi

if ! command -v bundle >/dev/null 2>&1; then
  echo "Bundler is unavailable. Install Homebrew Ruby before running Fastlane." >&2
  exit 1
fi

export BUNDLE_GEMFILE="$REPO_ROOT/Gemfile"
export BUNDLE_PATH="${BUNDLE_PATH:-$REPO_ROOT/.build/fastlane-gems}"
export FASTLANE_SKIP_UPDATE_CHECK="1"
export MAESTRO_CLI_NO_ANALYTICS="1"
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED="true"

cd "$REPO_ROOT"

if ! bundle check >/dev/null 2>&1; then
  bundle install
fi

exec bundle exec fastlane "$@"
