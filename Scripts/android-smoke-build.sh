#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/android-smoke-build.sh [options]

Builds the Android Skip/Fuse app through one stable lane.

Options:
  --lane apk|module|both   Build lane to run. Default: apk.
                          apk:    installable Android wrapper via skip gradle.
                          module: native OpenMusicEventApp module via skip android build.
  --install                Install the APK after an apk/both build.
  --launch                 Launch the app after install. Implies --install.
  --logs                   Dump focused logcat output after launch/install.
  --serial SERIAL          Android device serial. Default: ANDROID_SERIAL or emulator-5554.
  --app-root PATH          Skip app package to build. Default: this OME checkout.
  --target TARGET          Skip module target for --lane module. Default: OpenMusicEventApp.
  --smoke-root PATH        Stable cache/scratch root. Default: /private/tmp/ome-android-smoke.
  --compiler-lock PATH     Android compiler lock. Default: /private/tmp/woody-swift-compiler-android.lock.
  --skip-local PATH        Local skipstone checkout. Default: SKIPLOCAL or ~/Developer/swift-packages/3rd-party/skip/skipstone.
  --skip-command PATH      Local SkipRunner executable. Default: SKIP_COMMAND_OVERRIDE or SMOKE_ROOT/skipstone-build/debug/SkipRunner.
  --gradle-bin PATH        Gradle executable. Default: GRADLE_BIN, then known /private/tmp installs.
  --no-prebuild            Set SKIP_ANDROID_PREBUILD=0 for the apk lane.
  --dry-run                Print the resolved environment and commands without executing them.
  -h, --help               Show this help.

Environment overrides:
  JAVA_HOME, ANDROID_HOME, ANDROID_SDK_ROOT, ANDROID_USER_HOME, GRADLE_USER_HOME, SKIPLOCAL,
  SKIP_COMMAND_OVERRIDE, SKIP_SHARING_SWIFT_SHARING,
  CLANG_MODULE_CACHE_PATH, SWIFT_MODULECACHE_PATH, CFFIXED_USER_HOME,
  SWIFT_SDK_HOME, SWIFT_ANDROID_SDK_BUNDLE, SWIFT_TOOLCHAIN_DIR,
  OME_ANDROID_APP_BUILD, OME_ANDROID_COMPILER_LOCK_FILE, OME_ANDROID_SKIPSTONE_BUILD_ROOT,
  OME_ANDROID_NATIVE_BUILD_CONFIG_FILE,
  SWIFT_COMPILER_LANE_SCRIPT, ANDROID_SERIAL, ANDROID_APPLICATION_ID, LOGCAT_FILTERS.
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/.." && pwd
}

first_executable() {
  local candidate
  for candidate in "$@"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

read_skip_env_value() {
  local key="$1"
  local file="$2"
  awk -F= -v key="$key" '
    $0 !~ /^[[:space:]]*\/\// && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$file"
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    "$@"
  fi
}

ROOT="$(repo_root)"
APP_ROOT="$ROOT"
SCRIPT_PATH="$ROOT/Scripts/android-smoke-build.sh"
COMPILER_LANE_COMMAND=(env OME_ANDROID_COMPILER_LANE_ACTIVE=1 "$SCRIPT_PATH")
if [[ $# -gt 0 ]]; then
  COMPILER_LANE_COMMAND+=("$@")
fi
LANE="apk"
INSTALL=0
LAUNCH=0
LOGS=0
DRY_RUN=0
MODULE_TARGET="OpenMusicEventApp"
ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
SMOKE_ROOT="${OME_ANDROID_SMOKE_ROOT:-/private/tmp/ome-android-smoke}"
COMPILER_LOCK_FILE="${OME_ANDROID_COMPILER_LOCK_FILE:-/private/tmp/woody-swift-compiler-android.lock}"
COMPILER_LANE_SCRIPT="${SWIFT_COMPILER_LANE_SCRIPT:-${HOME}/.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh}"
COMPILER_LANE_ACTIVE="${OME_ANDROID_COMPILER_LANE_ACTIVE:-0}"
SKIP_ANDROID_PREBUILD="${SKIP_ANDROID_PREBUILD:-1}"
GRADLE_BIN="${GRADLE_BIN:-}"
SKIPLOCAL="${SKIPLOCAL:-${HOME}/Developer/swift-packages/3rd-party/skip/skipstone}"
SKIP_COMMAND_OVERRIDE="${SKIP_COMMAND_OVERRIDE:-}"
SKIP_SHARING_SWIFT_SHARING="${SKIP_SHARING_SWIFT_SHARING:-$ROOT/../swift-sharing}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lane)
      [[ $# -ge 2 ]] || fail "--lane requires apk, module, or both"
      LANE="$2"
      shift 2
      ;;
    --install)
      INSTALL=1
      shift
      ;;
    --launch)
      INSTALL=1
      LAUNCH=1
      shift
      ;;
    --logs)
      LOGS=1
      shift
      ;;
    --serial)
      [[ $# -ge 2 ]] || fail "--serial requires a device serial"
      ANDROID_SERIAL="$2"
      shift 2
      ;;
    --app-root)
      [[ $# -ge 2 ]] || fail "--app-root requires a path"
      APP_ROOT="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || fail "--target requires a Skip target"
      MODULE_TARGET="$2"
      shift 2
      ;;
    --smoke-root)
      [[ $# -ge 2 ]] || fail "--smoke-root requires a path"
      SMOKE_ROOT="$2"
      shift 2
      ;;
    --compiler-lock)
      [[ $# -ge 2 ]] || fail "--compiler-lock requires a path"
      COMPILER_LOCK_FILE="$2"
      shift 2
      ;;
    --skip-local)
      [[ $# -ge 2 ]] || fail "--skip-local requires a path"
      SKIPLOCAL="$2"
      shift 2
      ;;
    --skip-command)
      [[ $# -ge 2 ]] || fail "--skip-command requires a path"
      SKIP_COMMAND_OVERRIDE="$2"
      shift 2
      ;;
    --gradle-bin)
      [[ $# -ge 2 ]] || fail "--gradle-bin requires a path"
      GRADLE_BIN="$2"
      shift 2
      ;;
    --no-prebuild)
      SKIP_ANDROID_PREBUILD=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

case "$LANE" in
  apk|module|both) ;;
  *) fail "--lane must be apk, module, or both" ;;
esac

APP_ROOT="$(cd "$APP_ROOT" && pwd -P)" || fail "app root does not exist: $APP_ROOT"

if [[ "$COMPILER_LANE_ACTIVE" != "1" ]]; then
  [[ -x "$COMPILER_LANE_SCRIPT" ]] || fail "compiler lane script is not executable: $COMPILER_LANE_SCRIPT"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    "$COMPILER_LANE_SCRIPT" \
      --repo "$APP_ROOT" \
      --lock-file "$COMPILER_LOCK_FILE" \
      --dry-run \
      exec "${COMPILER_LANE_COMMAND[@]}"
    COMPILER_LANE_ACTIVE=1
  else
    exec "$COMPILER_LANE_SCRIPT" \
      --repo "$APP_ROOT" \
      --lock-file "$COMPILER_LOCK_FILE" \
      exec "${COMPILER_LANE_COMMAND[@]}"
  fi
fi

SKIPSTONE_BUILD_ROOT="${OME_ANDROID_SKIPSTONE_BUILD_ROOT:-$SMOKE_ROOT/skipstone-build}"
SKIPSTONE_SWIFTPM_ROOT="$SMOKE_ROOT/skipstone-swiftpm"

if [[ -z "$GRADLE_BIN" ]]; then
  GRADLE_BIN="$(first_executable \
    "/private/tmp/gradle-9.0.0/bin/gradle" \
    "/tmp/gradle-9.5.0/bin/gradle" \
    "/private/tmp/gradle-9.5.0/bin/gradle" \
  )" || fail "could not find a pinned Gradle; set GRADLE_BIN"
fi

if [[ -z "$SKIP_COMMAND_OVERRIDE" ]]; then
  SKIP_COMMAND_OVERRIDE="$SKIPSTONE_BUILD_ROOT/debug/SkipRunner"
fi

[[ -d "$SKIPLOCAL" ]] || fail "SKIPLOCAL does not exist: $SKIPLOCAL"
[[ -d "$SKIP_SHARING_SWIFT_SHARING" ]] || fail "local swift-sharing does not exist: $SKIP_SHARING_SWIFT_SHARING"
[[ -x "$GRADLE_BIN" ]] || fail "Gradle is not executable: $GRADLE_BIN"
[[ -d "$APP_ROOT/Android" ]] || fail "Android project not found at $APP_ROOT/Android"
[[ -f "$APP_ROOT/Skip.env" ]] || fail "Skip.env not found at $APP_ROOT/Skip.env"

export JAVA_HOME="${JAVA_HOME:-/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-${HOME}/.android}"
export SKIPLOCAL
export SKIP_COMMAND_OVERRIDE
export SKIP_SHARING_SWIFT_SHARING
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$SMOKE_ROOT/gradle-user-home}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$SMOKE_ROOT/clang-module-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$SMOKE_ROOT/swift-module-cache}"
export CFFIXED_USER_HOME="${CFFIXED_USER_HOME:-$SMOKE_ROOT/swiftpm-home}"
export SWIFT_SDK_HOME="${SWIFT_SDK_HOME:-${HOME}/Library/org.swift.swiftpm/swift-sdks}"
export SWIFT_ANDROID_SDK_BUNDLE="${SWIFT_ANDROID_SDK_BUNDLE:-$SWIFT_SDK_HOME/swift-6.3.3-RELEASE_android.artifactbundle}"
export SWIFT_TOOLCHAIN_DIR="${SWIFT_TOOLCHAIN_DIR:-${HOME}/Library/Developer/Toolchains}"
export OME_ANDROID_APP_BUILD="${OME_ANDROID_APP_BUILD:-1}"
export SKIP_ANDROID_PREBUILD
export ANDROID_SERIAL
export PATH="$(dirname "$GRADLE_BIN"):$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/local/bin:$PATH"

[[ -d "$JAVA_HOME" ]] || fail "JAVA_HOME does not exist: $JAVA_HOME"
[[ -d "$ANDROID_HOME" ]] || fail "ANDROID_HOME does not exist: $ANDROID_HOME"

if [[ "$DRY_RUN" -eq 0 ]]; then
  mkdir -p \
    "$SMOKE_ROOT" \
    "$ANDROID_USER_HOME" \
    "$GRADLE_USER_HOME" \
    "$CLANG_MODULE_CACHE_PATH" \
    "$SWIFT_MODULECACHE_PATH" \
    "$CFFIXED_USER_HOME" \
    "$SMOKE_ROOT/bin" \
    "$SKIPSTONE_BUILD_ROOT" \
    "$SKIPSTONE_SWIFTPM_ROOT/cache" \
    "$SKIPSTONE_SWIFTPM_ROOT/config" \
    "$SKIPSTONE_SWIFTPM_ROOT/security"
fi

ANDROID_APPLICATION_ID="${ANDROID_APPLICATION_ID:-$(read_skip_env_value ANDROID_APPLICATION_ID "$APP_ROOT/Skip.env")}"
if [[ -z "$ANDROID_APPLICATION_ID" ]]; then
  ANDROID_APPLICATION_ID="$(read_skip_env_value PRODUCT_BUNDLE_IDENTIFIER "$APP_ROOT/Skip.env")"
fi
[[ -n "$ANDROID_APPLICATION_ID" ]] || fail "could not determine Android application id from Skip.env"

MODULE_SCRATCH_PATH="${SKIP_SCRATCH_PATH:-$SMOKE_ROOT/skip-android-build}"
NATIVE_BUILD_CONFIG_FILE="${OME_ANDROID_NATIVE_BUILD_CONFIG_FILE:-$SMOKE_ROOT/android-native-build-config}"

verify_swift_sdks() {
  local isolated_sdk_home="$CFFIXED_USER_HOME/Library/org.swift.swiftpm/swift-sdks"
  local sdk_link

  [[ -d "$SWIFT_SDK_HOME" ]] || fail "Swift SDK directory does not exist: $SWIFT_SDK_HOME"
  [[ -d "$SWIFT_ANDROID_SDK_BUNDLE" ]] || fail "Swift Android SDK artifact bundle does not exist: $SWIFT_ANDROID_SDK_BUNDLE"
  [[ -d "$SWIFT_TOOLCHAIN_DIR" ]] || fail "Swift toolchain directory does not exist: $SWIFT_TOOLCHAIN_DIR"

  mkdir -p "$isolated_sdk_home"
  for sdk_link in "$isolated_sdk_home"/*android*.artifactbundle; do
    [[ -L "$sdk_link" ]] || continue
    [[ "$(basename "$sdk_link")" == "$(basename "$SWIFT_ANDROID_SDK_BUNDLE")" ]] || unlink "$sdk_link"
  done
  ln -sfn "$SWIFT_ANDROID_SDK_BUNDLE" "$isolated_sdk_home/$(basename "$SWIFT_ANDROID_SDK_BUNDLE")"
}

ensure_skip_command() {
  local rebuild=0
  if [[ ! -x "$SKIP_COMMAND_OVERRIDE" ]]; then
    rebuild=1
  elif find "$SKIPLOCAL/Package.swift" "$SKIPLOCAL/Sources" -type f -newer "$SKIP_COMMAND_OVERRIDE" -print -quit | rg -q .; then
    rebuild=1
  fi

  if [[ "$rebuild" -eq 1 ]]; then
    echo "Building local SkipRunner because the pinned executable is missing or stale"
    run swift build \
      --package-path "$SKIPLOCAL" \
      --product SkipRunner \
      --scratch-path "$SKIPSTONE_BUILD_ROOT" \
      --cache-path "$SKIPSTONE_SWIFTPM_ROOT/cache" \
      --config-path "$SKIPSTONE_SWIFTPM_ROOT/config" \
      --security-path "$SKIPSTONE_SWIFTPM_ROOT/security"
  fi

  [[ -x "$SKIP_COMMAND_OVERRIDE" ]] || fail "local SkipRunner is not executable: $SKIP_COMMAND_OVERRIDE"
}

# Gradle daemons outlive the shell that launched them and therefore do not
# reliably inherit SKIPLOCAL. The generated Fuse build does explicitly forward
# SKIP_COMMAND_OVERRIDE, so route that command through a stable wrapper that
# restores the local toolchain selection for every nested SwiftPM invocation.
configure_nested_skip_command() {
  local skip_runner_command="$SKIP_COMMAND_OVERRIDE"
  local skip_command_wrapper="$SMOKE_ROOT/bin/SkipRunner-observation-aware"
  local quoted_skiplocal
  local quoted_skip_runner
  local quoted_wrapper

  printf -v quoted_skiplocal '%q' "$SKIPLOCAL"
  printf -v quoted_skip_runner '%q' "$skip_runner_command"
  printf -v quoted_wrapper '%q' "$skip_command_wrapper"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
      printf 'export SKIPLOCAL=%s\n' "$quoted_skiplocal"
      printf 'export SKIP_COMMAND_OVERRIDE=%s\n' "$quoted_wrapper"
      printf 'exec %s "$@"\n' "$quoted_skip_runner"
    } > "$skip_command_wrapper"
    chmod +x "$skip_command_wrapper"
  fi

  SKIP_RUNNER_COMMAND="$skip_runner_command"
  SKIP_COMMAND_OVERRIDE="$skip_command_wrapper"
  export SKIP_COMMAND_OVERRIDE
}

if [[ "$DRY_RUN" -eq 0 ]]; then
  verify_swift_sdks
  ensure_skip_command
fi
configure_nested_skip_command

echo "Android smoke build"
echo "  wiring repo: $ROOT"
echo "  app root:    $APP_ROOT"
echo "  lane:        $LANE"
echo "  compiler lock: $COMPILER_LOCK_FILE"
echo "  skip runner: $SKIP_RUNNER_COMMAND"
echo "  nested skip: $SKIP_COMMAND_OVERRIDE"
echo "  skip build:  $SKIPSTONE_BUILD_ROOT"
echo "  SKIPLOCAL:   $SKIPLOCAL"
echo "  Sharing:     $SKIP_SHARING_SWIFT_SHARING"
echo "  JAVA_HOME:   $JAVA_HOME"
echo "  Android home: $ANDROID_USER_HOME"
echo "  Gradle:      $GRADLE_BIN"
echo "  smoke root:  $SMOKE_ROOT"
echo "  Swift SDKs:  $SWIFT_SDK_HOME"
echo "  Android SDK: $SWIFT_ANDROID_SDK_BUNDLE"
echo "  toolchains:  $SWIFT_TOOLCHAIN_DIR"
echo "  serial:      $ANDROID_SERIAL"
echo "  app id:      $ANDROID_APPLICATION_ID"
echo "  android app: $OME_ANDROID_APP_BUILD"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  dry run:     yes"
fi

build_module() {
  run "$SKIP_COMMAND_OVERRIDE" android build \
    --package-path "$APP_ROOT" \
    --scratch-path "$MODULE_SCRATCH_PATH" \
    --configuration debug \
    --plain \
    --verbose \
    --target "$MODULE_TARGET"
}

native_build_config() {
  cat <<CONFIG
version=2
swift_android_sdk_bundle=$SWIFT_ANDROID_SDK_BUNDLE
swift_toolchain_dir=$SWIFT_TOOLCHAIN_DIR
skiplocal=$SKIPLOCAL
skip_command=$SKIP_COMMAND_OVERRIDE
skip_runner=$SKIP_RUNNER_COMMAND
skip_sharing_swift_sharing=$SKIP_SHARING_SWIFT_SHARING
ome_android_app_build=$OME_ANDROID_APP_BUILD
CONFIG
}

# A stale compatibility module makes unrelated packages' canImport(SwiftUI)
# branches depend on incremental build order, exposing undeclared CJNI or MachO imports.
invalidate_stale_swiftui_modules() {
  local generated_root
  local metadata
  local module
  local package_manifest
  local package_resolved
  local should_invalidate
  local config_changed=0

  if [[ -f "$NATIVE_BUILD_CONFIG_FILE" ]] && ! cmp -s "$NATIVE_BUILD_CONFIG_FILE" <(native_build_config); then
    config_changed=1
  fi

  while IFS= read -r -d '' module; do
    generated_root="${module%%/build/swift/*}"
    package_manifest="$generated_root/src/main/swift/Package.swift"
    package_resolved="$generated_root/src/main/swift/Package.resolved"
    should_invalidate="$config_changed"

    if [[ -f "$package_manifest" && "$package_manifest" -nt "$module" ]]; then
      should_invalidate=1
    fi
    if [[ -f "$package_resolved" && "$package_resolved" -nt "$module" ]]; then
      should_invalidate=1
    fi
    [[ "$should_invalidate" -eq 1 ]] || continue

    echo "Invalidating stale Android SwiftUI module metadata: $module"
    for metadata in \
      "$module" \
      "${module%.swiftmodule}.swiftdoc" \
      "${module%.swiftmodule}.swiftsourceinfo"
    do
      [[ -e "$metadata" ]] || continue
      run rm -f "$metadata"
    done
  done < <(
    find "$APP_ROOT/.build/plugins/outputs" \
      -type f \
      -path '*/build/swift/*-unknown-linux-android*/debug/Modules/SwiftUI.swiftmodule' \
      -print0 2>/dev/null
  )
}

verify_observation_bridges() {
  local bridge
  local bridge_count=0
  local failure_count=0

  while IFS= read -r -d '' bridge; do
    bridge_count=$((bridge_count + 1))
    if ! rg -q 'withObservationTracking' "$bridge"; then
      echo "error: generated OME bridge is not observation-aware: $bridge" >&2
      failure_count=$((failure_count + 1))
    fi
  done < <(
    find "$APP_ROOT/.build/plugins/outputs" \
      -type f \
      -path '*/SkipBridgeGenerated/OpenMusicEventAppRoot_Bridge.swift' \
      -print0 2>/dev/null
  )

  [[ "$bridge_count" -gt 0 ]] || fail "no generated OpenMusicEventAppRoot bridge found under $APP_ROOT/.build/plugins/outputs"
  [[ "$failure_count" -eq 0 ]] || fail "$failure_count generated OME observation bridge(s) used the wrong Skipstone toolchain"
  echo "Verified $bridge_count observation-aware generated OME bridge(s)"
}

verify_periodic_timeline_bridges() {
  local bridge
  local bridge_count=0
  local failure_count=0

  while IFS= read -r -d '' bridge; do
    bridge_count=$((bridge_count + 1))
    if ! rg -q 'extension PeriodicTimelineView: BridgedToKotlin, SkipUIBridging, SkipUI.View' "$bridge"; then
      echo "error: generated periodic timeline view does not bridge to SkipUI: $bridge" >&2
      failure_count=$((failure_count + 1))
    fi
    if ! rg -q 'Java_initState_currentDate' "$bridge"; then
      echo "error: generated periodic timeline view does not bridge its current date state: $bridge" >&2
      failure_count=$((failure_count + 1))
    fi
  done < <(
    find "$APP_ROOT/.build/plugins/outputs" \
      -type f \
      -path '*/SkipBridgeGenerated/PeriodicTimelineView_Bridge.swift' \
      -print0 2>/dev/null
  )

  [[ "$bridge_count" -gt 0 ]] || fail "no generated PeriodicTimelineView bridge found under $APP_ROOT/.build/plugins/outputs"
  [[ "$failure_count" -eq 0 ]] || fail "$failure_count generated periodic timeline bridge check(s) failed"
  echo "Verified $bridge_count periodic timeline generated bridge(s)"
}

record_native_build_config() {
  if [[ "$DRY_RUN" -eq 0 ]]; then
    native_build_config > "$NATIVE_BUILD_CONFIG_FILE"
  fi
}

build_apk() {
  invalidate_stale_swiftui_modules
  run "$SKIP_COMMAND_OVERRIDE" gradle -p "$APP_ROOT/Android" :app:assembleDebug
  if [[ "$DRY_RUN" -eq 0 ]]; then
    verify_observation_bridges
    verify_periodic_timeline_bridges
  fi
  record_native_build_config
}

apk_path() {
  local output_dir

  for output_dir in \
    "$APP_ROOT/.build/Android/app/outputs/apk/debug" \
    "$APP_ROOT/Android/app/build/outputs/apk/debug"
  do
    [[ -d "$output_dir" ]] || continue
    find "$output_dir" -type f -name '*.apk' -print
  done | sort | tail -n 1
}

case "$LANE" in
  module)
    build_module
    ;;
  apk)
    build_apk
    ;;
  both)
    build_module
    build_apk
    ;;
esac

if [[ "$DRY_RUN" -eq 0 && ( "$INSTALL" -eq 1 || "$LOGS" -eq 1 ) ]]; then
  command -v adb >/dev/null || fail "adb is not on PATH"
fi

if [[ "$INSTALL" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    APK_PATH="$APP_ROOT/.build/Android/app/outputs/apk/debug/app-debug.apk"
  else
    APK_PATH="$(apk_path)"
    [[ -n "$APK_PATH" ]] || fail "no debug APK found under Android/app/build/outputs/apk/debug"
  fi
  run adb -s "$ANDROID_SERIAL" install -r "$APK_PATH"
fi

if [[ "$LAUNCH" -eq 1 ]]; then
  run adb -s "$ANDROID_SERIAL" shell am force-stop "$ANDROID_APPLICATION_ID"
  run adb -s "$ANDROID_SERIAL" shell monkey -p "$ANDROID_APPLICATION_ID" 1
fi

if [[ "$LOGS" -eq 1 ]]; then
  LOGCAT_FILTERS="${LOGCAT_FILTERS:-$ANDROID_APPLICATION_ID/OpenMusicEventApp OpenMusicEvent AndroidRuntime SwiftRuntime skip.ui.SkipUI}"
  # shellcheck disable=SC2086
  run adb -s "$ANDROID_SERIAL" logcat -d -v time -s $LOGCAT_FILTERS
fi
