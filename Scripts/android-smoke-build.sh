#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/android-smoke-build.sh [options]

Builds the Android Skip/Fuse app through the generated Gradle app lane, or runs
the app test target inside an Android instrumentation APK.

Options:
  --tests                  Run OpenMusicEventAppTests in an instrumentation APK instead of building the app.
  --compose-tests          Run the Compose fixture tests on the selected Android device.
  --configuration NAME    Build configuration: debug or release. Default: debug.
  --artifact apk|bundle   Android wrapper artifact. Default: apk.
                          bundle produces an AAB and cannot be installed directly.
  --architectures LIST    Comma-separated Android Swift architectures.
                          Release default: aarch64,x86_64. Debug default: Skip automatic.
  --install                Install the APK after the app build.
  --clear-data             Clear the installed package data after install. Implies --install.
  --launch                 Launch the app after install. Implies --install.
  --run-installed          Clear, launch, or inspect the existing app without building or installing.
  --logs                   Dump focused logcat output after launch/install.
  --serial SERIAL          Android device serial. Default: ANDROID_SERIAL or emulator-5554.
  --app-root PATH          Skip app package to build. Default: this OME checkout.
  --open-music-event-path PATH
                          OME package used by an external app root. Default: this checkout.
  --composable-notifications PATH
                          Local ComposableNotifications checkout. Default: the Android workspace route.
  --composable-atmosphere-tangled PATH
                          Local Tangled integration checkout. Default: the Android workspace route.
  --composable-workspace PATH
                          Local ComposableWorkspace checkout. Default: the remote package.
  --dependencies-http-client PATH
                          Local HTTP client checkout. Default: the Android workspace route.
  --smoke-root PATH        Stable cache/scratch root. External app roots get their own namespace.
  --skip-local PATH        Local skipstone checkout. Default: SKIPLOCAL or ~/Developer/swift-packages/3rd-party/skip/skipstone.
  --skip-command PATH      Local SkipRunner executable. Default: SKIP_COMMAND_OVERRIDE or SMOKE_ROOT/skipstone-build/debug/SkipRunner.
  --adopt-build-config     Explicitly replace pinned build inputs after a successful app build.
  --gradle-bin PATH        Gradle executable. Default: GRADLE_BIN, then known /private/tmp installs.
  --no-prebuild            Set SKIP_ANDROID_PREBUILD=0 for the app build.
  --dry-run                Print the resolved environment and commands without executing them.
  -h, --help               Show this help.

Environment overrides:
  JAVA_HOME, ANDROID_HOME, ANDROID_SDK_ROOT, ANDROID_USER_HOME, GRADLE_USER_HOME, SKIPLOCAL,
  SKIP_COMMAND_OVERRIDE, SKIP_SHARING_SWIFT_SHARING, SKIP_EXPORT_ARCHS,
  CLANG_MODULE_CACHE_PATH, SWIFT_MODULECACHE_PATH, CFFIXED_USER_HOME,
  SWIFT_SDK_HOME, SWIFT_ANDROID_SDK_BUNDLE, SWIFT_TOOLCHAIN_DIR,
  OME_ANDROID_APP_BUILD, OME_UI_AUTOMATION, OME_OPEN_MUSIC_EVENT_PATH, OME_TCA26_PATH,
  OME_COMPOSABLE_NOTIFICATIONS_PATH, OME_COMPOSABLE_ATMOSPHERE_TANGLED_PATH,
  OME_COMPOSABLE_WORKSPACE_PATH,
  OME_DEPENDENCIES_HTTP_CLIENT_PATH,
  OME_ANDROID_TEST_APP_APK, OME_ANDROID_TEST_FILTER, OME_ANDROID_TEST_PARALLELISM,
  OME_ANDROID_SKIPSTONE_BUILD_ROOT,
  OME_ANDROID_NATIVE_BUILD_CONFIG_FILE, OME_ANDROID_PACKAGE_RESOLUTION_CONFIG_FILE,
  OME_ANDROID_ARCHITECTURES,
  ANDROID_SERIAL, ANDROID_APPLICATION_ID, LOGCAT_FILTERS.
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

read_build_config_value() {
  local key="$1"
  local file="$2"

  awk -v key="$key" '
    index($0, key "=") == 1 {
      print substr($0, length(key) + 2)
      found = 1
      exit
    }
    END {
      if (!found) exit 1
    }
  ' "$file"
}

logical_absolute_path() {
  local path="$1"
  local directory

  directory="$(cd -L "$(dirname "$path")" && pwd -L)"
  printf '%s/%s\n' "$directory" "$(basename "$path")"
}

package_absolute_path() {
  local package_root="$1"
  local path="$2"

  case "$path" in
    /*) logical_absolute_path "$path" ;;
    *) logical_absolute_path "$package_root/$path" ;;
  esac
}

android_workspace_package_path() {
  local package_root="$1"
  local package_name="$2"
  local workspace_container
  local workspace_root
  local candidate

  workspace_container="$(dirname "$package_root")"
  if [[ "$(basename "$workspace_container")" == "worktrees" ]]; then
    workspace_root="$(dirname "$workspace_container")"
  else
    workspace_root="$workspace_container"
  fi

  for candidate in \
    "$workspace_root/worktrees/$package_name" \
    "$workspace_container/$package_name" \
    "$workspace_root/$package_name"
  do
    if [[ -d "$candidate" ]]; then
      logical_absolute_path "$candidate"
      return 0
    fi
  done

  logical_absolute_path "$workspace_root/worktrees/$package_name"
}

package_source_fingerprint() {
  local package_root="$1"
  local input

  {
    for input in \
      "$package_root"/Package*.swift \
      "$package_root/Package.resolved" \
      "$package_root/Plugins" \
      "$package_root/Sources"
    do
      [[ -e "$input" ]] || continue
      if [[ -d "$input" ]]; then
        find -L "$input" -type f -print0
      else
        printf '%s\0' "$input"
      fi
    done
  } \
    | LC_ALL=C sort -z \
    | xargs -0 shasum -a 256 \
    | sed "s#  $package_root/#  #" \
    | shasum -a 256 \
    | awk '{ print $1 }'
}

package_graph_fingerprint() {
  local package_root="$1"
  local input

  {
    for input in "$package_root"/Package*.swift "$package_root/Package.resolved"; do
      [[ -f "$input" ]] || continue
      printf '%s  %s\n' \
        "$(shasum -a 256 "$input" | awk '{ print $1 }')" \
        "${input#"$package_root"/}"
    done
  } \
    | LC_ALL=C sort \
    | shasum -a 256 \
    | awk '{ print $1 }'
}

android_package_input_manifest() {
  local descriptor
  local package_name
  local package_path
  local resolved_path

  printf 'open-music-event-package-graph=%s|%s\n' \
    "$OME_PACKAGE_ROOT" \
    "$(package_graph_fingerprint "$OME_PACKAGE_ROOT")"
  for descriptor in "${ANDROID_LOCAL_PACKAGE_INPUTS[@]}"; do
    package_name="${descriptor%%|*}"
    package_path="${descriptor#*|}"
    resolved_path="$(cd "$package_path" && pwd -P)"
    printf '%s=%s|%s|%s\n' \
      "$package_name" \
      "$package_path" \
      "$resolved_path" \
      "$(package_source_fingerprint "$resolved_path")"
  done
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
launch_android_app() {
  local component
  if [[ "$DRY_RUN" -eq 1 ]]; then
    run adb -s "$ANDROID_SERIAL" shell cmd package resolve-activity --brief "$ANDROID_APPLICATION_ID"
    component="$ANDROID_APPLICATION_ID/<resolved-launcher>"
  else
    component="$(adb -s "$ANDROID_SERIAL" shell cmd package resolve-activity --brief "$ANDROID_APPLICATION_ID" | tr -d '\r' | tail -n 1)"
    [[ "$component" == "$ANDROID_APPLICATION_ID/"* ]] \
      || fail "could not resolve launcher activity for $ANDROID_APPLICATION_ID: $component"
  fi
  run adb -s "$ANDROID_SERIAL" shell am start -W -n "$component"
}

RUN_TESTS=0
RUN_COMPOSE_TESTS=0
RUN_INSTALLED=0
CONFIGURATION="debug"
CONFIGURATION_EXPLICIT=0
ARTIFACT="apk"
ARCHITECTURES="${OME_ANDROID_ARCHITECTURES:-${SKIP_EXPORT_ARCHS:-}}"
ARCHITECTURES_EXPLICIT=0
if [[ -n "${OME_ANDROID_ARCHITECTURES+x}" || -n "${SKIP_EXPORT_ARCHS+x}" ]]; then
  ARCHITECTURES_EXPLICIT=1
fi
INSTALL=0
INSTALL_EXPLICIT=0
CLEAR_DATA=0
LAUNCH=0
LOGS=0
DRY_RUN=0
ADOPT_BUILD_CONFIG=0
APP_MODULE_TARGET="OpenMusicEventApp"
ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
SMOKE_ROOT_EXPLICIT=0
if [[ -n "${OME_ANDROID_SMOKE_ROOT+x}" ]]; then
  SMOKE_ROOT_EXPLICIT=1
fi
SMOKE_ROOT="${OME_ANDROID_SMOKE_ROOT:-/private/tmp/ome-android-smoke}"
SKIP_ANDROID_PREBUILD="${SKIP_ANDROID_PREBUILD:-1}"
GRADLE_BIN="${GRADLE_BIN:-}"
SKIPLOCAL_EXPLICIT=0
if [[ -n "${SKIPLOCAL+x}" ]]; then
  SKIPLOCAL_EXPLICIT=1
fi
SKIPLOCAL="${SKIPLOCAL:-${HOME}/Developer/swift-packages/3rd-party/skip/skipstone}"
SKIP_COMMAND_OVERRIDE="${SKIP_COMMAND_OVERRIDE:-}"
SKIP_COMMAND_MANAGED=1
if [[ -n "$SKIP_COMMAND_OVERRIDE" ]]; then
  SKIP_COMMAND_MANAGED=0
fi
SKIP_SHARING_EXPLICIT=0
if [[ -n "${SKIP_SHARING_SWIFT_SHARING+x}" ]]; then
  SKIP_SHARING_EXPLICIT=1
fi
SKIP_SHARING_SWIFT_SHARING="${SKIP_SHARING_SWIFT_SHARING:-}"
SWIFT_SDK_HOME_EXPLICIT=0
[[ -z "${SWIFT_SDK_HOME+x}" ]] || SWIFT_SDK_HOME_EXPLICIT=1
SWIFT_SDK_HOME="${SWIFT_SDK_HOME:-${HOME}/Library/org.swift.swiftpm/swift-sdks}"
SWIFT_ANDROID_SDK_BUNDLE_EXPLICIT=0
if [[ -n "${SWIFT_ANDROID_SDK_BUNDLE+x}" ]]; then
  SWIFT_ANDROID_SDK_BUNDLE_EXPLICIT=1
fi
SWIFT_ANDROID_SDK_BUNDLE="${SWIFT_ANDROID_SDK_BUNDLE:-$SWIFT_SDK_HOME/swift-6.3.3-RELEASE_android.artifactbundle}"
SWIFT_TOOLCHAIN_DIR_EXPLICIT=0
if [[ -n "${SWIFT_TOOLCHAIN_DIR+x}" ]]; then
  SWIFT_TOOLCHAIN_DIR_EXPLICIT=1
fi
SWIFT_TOOLCHAIN_DIR="${SWIFT_TOOLCHAIN_DIR:-${HOME}/Library/Developer/Toolchains}"
OME_ANDROID_APP_BUILD_EXPLICIT=0
if [[ -n "${OME_ANDROID_APP_BUILD+x}" ]]; then
  OME_ANDROID_APP_BUILD_EXPLICIT=1
fi
OME_ANDROID_APP_BUILD="${OME_ANDROID_APP_BUILD:-1}"
OME_OPEN_MUSIC_EVENT_PATH="${OME_OPEN_MUSIC_EVENT_PATH:-}"
OME_TCA26_PATH="${OME_TCA26_PATH:-}"
COMPOSABLE_NOTIFICATIONS_PATH="${OME_COMPOSABLE_NOTIFICATIONS_PATH:-}"
COMPOSABLE_ATMOSPHERE_TANGLED_PATH="${OME_COMPOSABLE_ATMOSPHERE_TANGLED_PATH:-}"
COMPOSABLE_WORKSPACE_PATH="${OME_COMPOSABLE_WORKSPACE_PATH:-}"
DEPENDENCIES_HTTP_CLIENT_PATH="${OME_DEPENDENCIES_HTTP_CLIENT_PATH:-}"
ANDROID_TEST_PARALLELISM="${OME_ANDROID_TEST_PARALLELISM:-1}"
ANDROID_TEST_FILTER="${OME_ANDROID_TEST_FILTER:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tests)
      RUN_TESTS=1
      shift
      ;;
    --compose-tests)
      RUN_TESTS=1
      RUN_COMPOSE_TESTS=1
      shift
      ;;
    --configuration)
      [[ $# -ge 2 ]] || fail "--configuration requires debug or release"
      CONFIGURATION="$2"
      CONFIGURATION_EXPLICIT=1
      shift 2
      ;;
    --artifact)
      [[ $# -ge 2 ]] || fail "--artifact requires apk or bundle"
      ARTIFACT="$2"
      shift 2
      ;;
    --architectures)
      [[ $# -ge 2 ]] || fail "--architectures requires a comma-separated list"
      ARCHITECTURES="$2"
      ARCHITECTURES_EXPLICIT=1
      shift 2
      ;;
    --install)
      INSTALL=1
      INSTALL_EXPLICIT=1
      shift
      ;;
    --clear-data)
      INSTALL=1
      CLEAR_DATA=1
      shift
      ;;
    --launch)
      INSTALL=1
      LAUNCH=1
      shift
      ;;
    --run-installed)
      RUN_INSTALLED=1
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
    --open-music-event-path)
      [[ $# -ge 2 ]] || fail "--open-music-event-path requires a path"
      OME_OPEN_MUSIC_EVENT_PATH="$2"
      shift 2
      ;;
    --composable-notifications)
      [[ $# -ge 2 ]] || fail "--composable-notifications requires a path"
      COMPOSABLE_NOTIFICATIONS_PATH="$2"
      shift 2
      ;;
    --composable-atmosphere-tangled)
      [[ $# -ge 2 ]] || fail "--composable-atmosphere-tangled requires a path"
      COMPOSABLE_ATMOSPHERE_TANGLED_PATH="$2"
      shift 2
      ;;
    --composable-workspace)
      [[ $# -ge 2 ]] || fail "--composable-workspace requires a path"
      COMPOSABLE_WORKSPACE_PATH="$2"
      shift 2
      ;;
    --dependencies-http-client)
      [[ $# -ge 2 ]] || fail "--dependencies-http-client requires a path"
      DEPENDENCIES_HTTP_CLIENT_PATH="$2"
      shift 2
      ;;
    --smoke-root)
      [[ $# -ge 2 ]] || fail "--smoke-root requires a path"
      SMOKE_ROOT="$2"
      SMOKE_ROOT_EXPLICIT=1
      shift 2
      ;;
    --skip-local)
      [[ $# -ge 2 ]] || fail "--skip-local requires a path"
      SKIPLOCAL="$2"
      SKIPLOCAL_EXPLICIT=1
      shift 2
      ;;
    --skip-command)
      [[ $# -ge 2 ]] || fail "--skip-command requires a path"
      SKIP_COMMAND_OVERRIDE="$2"
      SKIP_COMMAND_MANAGED=0
      shift 2
      ;;
    --adopt-build-config)
      ADOPT_BUILD_CONFIG=1
      shift
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

case "$ARTIFACT" in
  apk|bundle) ;;
  *) fail "--artifact must be apk or bundle" ;;
esac

if [[ "$ARTIFACT" == "bundle" && "$INSTALL" -eq 1 ]]; then
  fail "Android app bundles cannot be installed directly; use --artifact apk"
fi

if [[ "$RUN_INSTALLED" -eq 1 ]]; then
  [[ "$RUN_TESTS" -eq 0 ]] || fail "--run-installed cannot be combined with --tests"
  [[ "$INSTALL_EXPLICIT" -eq 0 ]] || fail "--run-installed cannot be combined with --install"
  [[ "$ARTIFACT" == "apk" ]] || fail "--run-installed cannot be combined with --artifact bundle"
  [[ "$ADOPT_BUILD_CONFIG" -eq 0 ]] || fail "--run-installed cannot adopt build configuration"
  [[ "$CLEAR_DATA" -eq 1 || "$LAUNCH" -eq 1 || "$LOGS" -eq 1 ]] \
    || fail "--run-installed requires --clear-data, --launch, or --logs"
fi

if [[ "$RUN_TESTS" -eq 1 ]]; then
  [[ "$ARTIFACT" == "apk" ]] || fail "--tests cannot be combined with --artifact bundle"
  [[ "$INSTALL" -eq 0 && "$CLEAR_DATA" -eq 0 && "$LAUNCH" -eq 0 && "$LOGS" -eq 0 ]] \
    || fail "--tests cannot be combined with --install, --clear-data, --launch, or --logs"
  [[ "$ADOPT_BUILD_CONFIG" -eq 0 ]] \
    || fail "--tests cannot adopt the app build configuration; run a successful app build instead"
  [[ "$ANDROID_TEST_PARALLELISM" =~ ^[1-9][0-9]*$ ]] \
    || fail "OME_ANDROID_TEST_PARALLELISM must be a positive integer"
fi

APP_ROOT="$(cd "$APP_ROOT" && pwd -P)" || fail "app root does not exist: $APP_ROOT"

if [[ "$RUN_INSTALLED" -eq 1 ]]; then
  ANDROID_APPLICATION_ID="${ANDROID_APPLICATION_ID:-$(read_skip_env_value ANDROID_APPLICATION_ID "$APP_ROOT/Skip.env")}"
  if [[ -z "$ANDROID_APPLICATION_ID" ]]; then
    ANDROID_APPLICATION_ID="$(read_skip_env_value PRODUCT_BUNDLE_IDENTIFIER "$APP_ROOT/Skip.env")"
  fi
  [[ -n "$ANDROID_APPLICATION_ID" ]] \
    || fail "could not determine Android application id from Skip.env"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    command -v adb >/dev/null || fail "adb is not on PATH"
  fi
  if [[ "$CLEAR_DATA" -eq 1 ]]; then
    run adb -s "$ANDROID_SERIAL" shell pm clear "$ANDROID_APPLICATION_ID"
  fi
  if [[ "$LAUNCH" -eq 1 ]]; then
    run adb -s "$ANDROID_SERIAL" shell am force-stop "$ANDROID_APPLICATION_ID"
    launch_android_app
  fi
  if [[ "$LOGS" -eq 1 ]]; then
    LOGCAT_FILTERS="${LOGCAT_FILTERS:-$ANDROID_APPLICATION_ID/OpenMusicEventApp OpenMusicEvent AndroidRuntime SwiftRuntime skip.ui.SkipUI}"
    # shellcheck disable=SC2086
    run adb -s "$ANDROID_SERIAL" logcat -d -v time -s $LOGCAT_FILTERS
  fi
  exit 0
fi

ANDROID_TEST_APP_APK="${OME_ANDROID_TEST_APP_APK:-$APP_ROOT/.build/Android/app/outputs/apk/$CONFIGURATION/app-$CONFIGURATION.apk}"
if [[ "$SMOKE_ROOT_EXPLICIT" -eq 0 ]]; then
  APP_ROOT_FINGERPRINT="$(printf '%s' "$APP_ROOT" | shasum -a 256 | cut -c 1-12)"
  SMOKE_ROOT="/private/tmp/ome-android-smoke-$(basename "$APP_ROOT")-$APP_ROOT_FINGERPRINT"
  if [[ "$RUN_COMPOSE_TESTS" -eq 1 ]]; then
    SMOKE_ROOT="$SMOKE_ROOT-compose"
  fi
fi
if [[ -z "$SKIP_SHARING_SWIFT_SHARING" ]]; then
  OME_WORKSPACE_CONTAINER="$(dirname "$ROOT")"
  if [[ "$(basename "$OME_WORKSPACE_CONTAINER")" == "worktrees" ]]; then
    OME_WORKSPACE_ROOT="$(dirname "$OME_WORKSPACE_CONTAINER")"
  else
    OME_WORKSPACE_ROOT="$OME_WORKSPACE_CONTAINER"
  fi
  for sharing_candidate in \
    "$(dirname "$SKIPLOCAL")/swift-sharing" \
    "$OME_WORKSPACE_ROOT/worktrees/swift-sharing" \
    "$OME_WORKSPACE_ROOT/swift-sharing"
  do
    if [[ -d "$sharing_candidate" ]]; then
      SKIP_SHARING_SWIFT_SHARING="$sharing_candidate"
      break
    fi
  done
  SKIP_SHARING_SWIFT_SHARING="${SKIP_SHARING_SWIFT_SHARING:-$OME_WORKSPACE_ROOT/worktrees/swift-sharing}"
fi
if [[ "$APP_ROOT" != "$ROOT" && -z "$OME_OPEN_MUSIC_EVENT_PATH" ]]; then
  OME_OPEN_MUSIC_EVENT_PATH="$ROOT"
fi
if [[ -n "$OME_OPEN_MUSIC_EVENT_PATH" ]]; then
  [[ -d "$OME_OPEN_MUSIC_EVENT_PATH" ]] \
    || fail "OME package path does not exist: $OME_OPEN_MUSIC_EVENT_PATH"
  OME_OPEN_MUSIC_EVENT_PATH="$(logical_absolute_path "$OME_OPEN_MUSIC_EVENT_PATH")"
  OME_OPEN_MUSIC_EVENT_PATH_RESOLVED="$(cd "$OME_OPEN_MUSIC_EVENT_PATH" && pwd -P)"
else
  OME_OPEN_MUSIC_EVENT_PATH_RESOLVED=""
fi
OME_PACKAGE_ROOT="${OME_OPEN_MUSIC_EVENT_PATH_RESOLVED:-$ROOT}"
if [[ -n "$OME_TCA26_PATH" ]]; then
  OME_TCA26_PATH="$(package_absolute_path "$OME_PACKAGE_ROOT" "$OME_TCA26_PATH")"
else
  OME_TCA26_PATH="$(android_workspace_package_path "$OME_PACKAGE_ROOT" TCA26)"
fi
if [[ -n "$COMPOSABLE_NOTIFICATIONS_PATH" ]]; then
  COMPOSABLE_NOTIFICATIONS_PATH="$(package_absolute_path "$OME_PACKAGE_ROOT" "$COMPOSABLE_NOTIFICATIONS_PATH")"
else
  COMPOSABLE_NOTIFICATIONS_PATH="$(android_workspace_package_path "$OME_PACKAGE_ROOT" swift-composable-notifications)"
fi
if [[ -n "$COMPOSABLE_ATMOSPHERE_TANGLED_PATH" ]]; then
  COMPOSABLE_ATMOSPHERE_TANGLED_PATH="$(package_absolute_path "$OME_PACKAGE_ROOT" "$COMPOSABLE_ATMOSPHERE_TANGLED_PATH")"
else
  COMPOSABLE_ATMOSPHERE_TANGLED_PATH="$(android_workspace_package_path "$OME_PACKAGE_ROOT" composable-atmosphere-tangled)"
fi
if [[ -n "$COMPOSABLE_WORKSPACE_PATH" ]]; then
  COMPOSABLE_WORKSPACE_PATH="$(package_absolute_path "$OME_PACKAGE_ROOT" "$COMPOSABLE_WORKSPACE_PATH")"
fi
if [[ -n "$DEPENDENCIES_HTTP_CLIENT_PATH" ]]; then
  DEPENDENCIES_HTTP_CLIENT_PATH="$(package_absolute_path "$OME_PACKAGE_ROOT" "$DEPENDENCIES_HTTP_CLIENT_PATH")"
else
  DEPENDENCIES_HTTP_CLIENT_PATH="$(android_workspace_package_path "$OME_PACKAGE_ROOT" swift-dependencies-http-client)"
fi
SKIPSTONE_BUILD_ROOT="${OME_ANDROID_SKIPSTONE_BUILD_ROOT:-$SMOKE_ROOT/skipstone-build}"
SKIPSTONE_SWIFTPM_ROOT="$SMOKE_ROOT/skipstone-swiftpm"
NATIVE_BUILD_CONFIG_FILE="${OME_ANDROID_NATIVE_BUILD_CONFIG_FILE:-$SMOKE_ROOT/android-native-build-config}"
SKIP_RUNNER_PROVENANCE_FILE="$SKIPSTONE_BUILD_ROOT/skip-runner-provenance"
ANDROID_NAMESPACE_INIT_SCRIPT="$SMOKE_ROOT/android-library-namespace.init.gradle.kts"
BUILD_CONFIG_STATE="new"

accept_or_reject_config_change() {
  local key="$1"
  local pinned="$2"
  local requested="$3"

  [[ "$pinned" != "$requested" ]] || return 0
  if [[ "$ADOPT_BUILD_CONFIG" -eq 1 ]]; then
    BUILD_CONFIG_STATE="adopting"
    echo "Adopting Android build config change: $key" >&2
    echo "  pinned:    $pinned" >&2
    echo "  requested: $requested" >&2
    return 0
  fi

  fail "Android build config drift for $key (pinned '$pinned', requested '$requested'); rerun with --adopt-build-config only for an intentional route change"
}

apply_pinned_config_value() {
  local key="$1"
  local variable_name="$2"
  local explicit="$3"
  local pinned
  local requested

  if ! pinned="$(read_build_config_value "$key" "$NATIVE_BUILD_CONFIG_FILE")"; then
    return 0
  fi
  if [[ "$key" == "architectures" && "$pinned" == "automatic" ]]; then
    pinned=""
  fi

  requested="${!variable_name}"
  if [[ "$explicit" -eq 1 ]]; then
    accept_or_reject_config_change "$key" "${pinned:-automatic}" "${requested:-automatic}"
  else
    printf -v "$variable_name" '%s' "$pinned"
  fi
}

check_pinned_config_value() {
  local key="$1"
  local requested="$2"
  local pinned

  if ! pinned="$(read_build_config_value "$key" "$NATIVE_BUILD_CONFIG_FILE")"; then
    return 0
  fi
  accept_or_reject_config_change "$key" "$pinned" "$requested"
}

if [[ -f "$NATIVE_BUILD_CONFIG_FILE" ]]; then
  if ! BUILD_CONFIG_VERSION="$(read_build_config_value version "$NATIVE_BUILD_CONFIG_FILE")"; then
    fail "Android build config is incomplete (missing version): $NATIVE_BUILD_CONFIG_FILE"
  fi
  case "$BUILD_CONFIG_VERSION" in
    2|3|4|5|6) ;;
    *) fail "unsupported Android build config version '$BUILD_CONFIG_VERSION': $NATIVE_BUILD_CONFIG_FILE" ;;
  esac
  for required_key in \
    swift_android_sdk_bundle \
    swift_toolchain_dir \
    skiplocal \
    skip_sharing_swift_sharing \
    ome_android_app_build \
    configuration \
    architectures
  do
    read_build_config_value "$required_key" "$NATIVE_BUILD_CONFIG_FILE" >/dev/null \
      || fail "Android build config v$BUILD_CONFIG_VERSION is incomplete (missing $required_key): $NATIVE_BUILD_CONFIG_FILE"
  done
  if [[ "$BUILD_CONFIG_VERSION" =~ ^(3|4|5|6)$ ]]; then
    for required_key in \
      app_root \
      skiplocal_resolved \
      skip_dependency_root \
      skip_dependency_root_resolved \
      skip_route_fingerprint \
      skip_sharing_swift_sharing_resolved
    do
      read_build_config_value "$required_key" "$NATIVE_BUILD_CONFIG_FILE" >/dev/null \
        || fail "Android build config v$BUILD_CONFIG_VERSION is incomplete (missing $required_key): $NATIVE_BUILD_CONFIG_FILE"
    done
  fi
  if [[ "$BUILD_CONFIG_VERSION" =~ ^(4|5|6)$ ]]; then
    for required_key in \
      ome_open_music_event_path \
      ome_open_music_event_path_resolved
    do
      read_build_config_value "$required_key" "$NATIVE_BUILD_CONFIG_FILE" >/dev/null \
        || fail "Android build config v$BUILD_CONFIG_VERSION is incomplete (missing $required_key): $NATIVE_BUILD_CONFIG_FILE"
    done
  fi
  if [[ "$BUILD_CONFIG_VERSION" =~ ^(5|6)$ ]]; then
    for required_key in \
      ome_open_music_event_path \
      ome_open_music_event_path_resolved \
      android_package_inputs_fingerprint
    do
      read_build_config_value "$required_key" "$NATIVE_BUILD_CONFIG_FILE" >/dev/null \
        || fail "Android build config v$BUILD_CONFIG_VERSION is incomplete (missing $required_key): $NATIVE_BUILD_CONFIG_FILE"
    done
  fi
  if [[ "$BUILD_CONFIG_VERSION" == "6" ]]; then
    read_build_config_value build_lane "$NATIVE_BUILD_CONFIG_FILE" >/dev/null \
      || fail "Android build config v6 is incomplete (missing build_lane): $NATIVE_BUILD_CONFIG_FILE"
  fi

  BUILD_CONFIG_STATE="pinned v$BUILD_CONFIG_VERSION"
  apply_pinned_config_value configuration CONFIGURATION "$CONFIGURATION_EXPLICIT"
  apply_pinned_config_value architectures ARCHITECTURES "$ARCHITECTURES_EXPLICIT"
  apply_pinned_config_value skiplocal SKIPLOCAL "$SKIPLOCAL_EXPLICIT"
  apply_pinned_config_value skip_sharing_swift_sharing SKIP_SHARING_SWIFT_SHARING "$SKIP_SHARING_EXPLICIT"
  apply_pinned_config_value swift_android_sdk_bundle SWIFT_ANDROID_SDK_BUNDLE "$SWIFT_ANDROID_SDK_BUNDLE_EXPLICIT"
  apply_pinned_config_value swift_toolchain_dir SWIFT_TOOLCHAIN_DIR "$SWIFT_TOOLCHAIN_DIR_EXPLICIT"
  apply_pinned_config_value ome_android_app_build OME_ANDROID_APP_BUILD "$OME_ANDROID_APP_BUILD_EXPLICIT"
fi

# Skip copies runtime libraries from SWIFT_SDK_HOME, while SwiftPM builds with
# the selected artifact bundle. Keep both consumers on the same SDK.
if [[ "$SWIFT_SDK_HOME_EXPLICIT" -eq 0 ]]; then
  SWIFT_SDK_HOME="$(dirname "$SWIFT_ANDROID_SDK_BUNDLE")"
fi

if [[ "${BUILD_CONFIG_VERSION:-0}" =~ ^(4|5|6)$ ]]; then
  check_pinned_config_value \
    ome_open_music_event_path \
    "${OME_OPEN_MUSIC_EVENT_PATH:-none}"
  check_pinned_config_value \
    ome_open_music_event_path_resolved \
    "${OME_OPEN_MUSIC_EVENT_PATH_RESOLVED:-none}"
fi

case "$CONFIGURATION" in
  debug) CONFIGURATION_SUFFIX="Debug" ;;
  release)
    CONFIGURATION_SUFFIX="Release"
    ARCHITECTURES="${ARCHITECTURES:-aarch64,x86_64}"
    ;;
  *) fail "--configuration must be debug or release" ;;
esac

if [[ -n "$ARCHITECTURES" ]]; then
  IFS=',' read -r -a REQUESTED_ARCHITECTURES <<< "$ARCHITECTURES"
  [[ "${#REQUESTED_ARCHITECTURES[@]}" -gt 0 ]] || fail "--architectures cannot be empty"
  for architecture in "${REQUESTED_ARCHITECTURES[@]}"; do
    case "$architecture" in
      aarch64|x86_64|armv7) ;;
      *) fail "unsupported Android Swift architecture: $architecture" ;;
    esac
  done
fi

[[ -d "$SKIPLOCAL" ]] || fail "SKIPLOCAL does not exist: $SKIPLOCAL"
[[ -d "$SKIP_SHARING_SWIFT_SHARING" ]] || fail "local swift-sharing does not exist: $SKIP_SHARING_SWIFT_SHARING"
SKIPLOCAL="$(logical_absolute_path "$SKIPLOCAL")"
SKIPLOCAL_RESOLVED="$(cd "$SKIPLOCAL" && pwd -P)"
SKIP_DEPENDENCY_ROOT="$(dirname "$SKIPLOCAL")"
SKIP_DEPENDENCY_ROOT_RESOLVED="$(cd "$SKIP_DEPENDENCY_ROOT" && pwd -P)"
SKIP_SHARING_SWIFT_SHARING="$(logical_absolute_path "$SKIP_SHARING_SWIFT_SHARING")"
SKIP_SHARING_SWIFT_SHARING_RESOLVED="$(cd "$SKIP_SHARING_SWIFT_SHARING" && pwd -P)"

ANDROID_LOCAL_PACKAGE_INPUTS=(
  "swift-hero-image-list|$(android_workspace_package_path "$OME_PACKAGE_ROOT" swift-hero-image-list)"
  "TCA26|$OME_TCA26_PATH"
  "composable-atmosphere-userinput|$(android_workspace_package_path "$OME_PACKAGE_ROOT" composable-atmosphere-userinput)"
  "swift-composable-notifications|$COMPOSABLE_NOTIFICATIONS_PATH"
  "swift-composable-forms|$(android_workspace_package_path "$OME_PACKAGE_ROOT" swift-composable-forms-android)"
  "swift-dependencies-http-client|$DEPENDENCIES_HTTP_CLIENT_PATH"
  "swift-composable-atmosphere|$(android_workspace_package_path "$OME_PACKAGE_ROOT" swift-composable-atmosphere)"
  "composable-atmosphere-constellation|$(android_workspace_package_path "$OME_PACKAGE_ROOT" composable-atmosphere-constellation)"
  "composable-atmosphere-tangled|$COMPOSABLE_ATMOSPHERE_TANGLED_PATH"
  "sqlite-data|$(android_workspace_package_path "$OME_PACKAGE_ROOT" sqlite-data)"
  "swift-structured-queries|$(android_workspace_package_path "$OME_PACKAGE_ROOT" swift-structured-queries)"
  "swift-sharing|$SKIP_SHARING_SWIFT_SHARING"
  "skipstone|$SKIPLOCAL"
  "skip|$SKIP_DEPENDENCY_ROOT/skip"
  "skip-ui|$SKIP_DEPENDENCY_ROOT/skip-ui"
  "skip-fuse-ui|$SKIP_DEPENDENCY_ROOT/skip-fuse-ui"
  "skip-sharing|$SKIP_DEPENDENCY_ROOT/skip-sharing"
  "skip-android-bridge|$SKIP_DEPENDENCY_ROOT/skip-android-bridge"
)
if [[ -d "$SKIP_DEPENDENCY_ROOT/skip-kit" ]]; then
  ANDROID_LOCAL_PACKAGE_INPUTS+=("skip-kit|$SKIP_DEPENDENCY_ROOT/skip-kit")
fi
if [[ -n "$COMPOSABLE_WORKSPACE_PATH" ]]; then
  ANDROID_LOCAL_PACKAGE_INPUTS+=("swift-composable-workspace|$COMPOSABLE_WORKSPACE_PATH")
fi
if [[ -n "${OME_FILE_TREE_PATH:-}" ]]; then
  ANDROID_LOCAL_PACKAGE_INPUTS+=("swift-file-tree|$OME_FILE_TREE_PATH")
fi
if [[ -n "${OME_CLOCKS_PATH:-}" ]]; then
  ANDROID_LOCAL_PACKAGE_INPUTS+=("swift-clocks|$OME_CLOCKS_PATH")
fi
if [[ -n "${OME_CUSTOM_DUMP_PATH:-}" ]]; then
  ANDROID_LOCAL_PACKAGE_INPUTS+=("swift-custom-dump|$OME_CUSTOM_DUMP_PATH")
fi
if [[ -n "${OME_SKIP_AUTHENTICATION_SERVICES_PATH:-}" ]]; then
  ANDROID_LOCAL_PACKAGE_INPUTS+=("skip-authentication-services|$OME_SKIP_AUTHENTICATION_SERVICES_PATH")
fi
if [[ -n "${OME_DEBUG_SNAPSHOTS_PATH:-}" ]]; then
  ANDROID_LOCAL_PACKAGE_INPUTS+=("swift-debug-snapshots|$OME_DEBUG_SNAPSHOTS_PATH")
fi
for package_input in "${ANDROID_LOCAL_PACKAGE_INPUTS[@]}"; do
  package_input_path="${package_input#*|}"
  [[ -d "$package_input_path" ]] \
    || fail "Android local package input does not exist: $package_input"
  [[ -f "$package_input_path/Package.swift" ]] \
    || fail "Android local package input has no Package.swift: $package_input"
done
ANDROID_PACKAGE_INPUT_MANIFEST="$(android_package_input_manifest)"
ANDROID_PACKAGE_INPUTS_FINGERPRINT="$(printf '%s\n' "$ANDROID_PACKAGE_INPUT_MANIFEST" | shasum -a 256 | awk '{ print $1 }')"

skip_route_manifest() {
  local package_name
  local package_path
  local resolved_path

  for package_name in skipstone skip skip-ui skip-fuse-ui skip-kit skip-sharing skip-android-bridge; do
    package_path="$SKIP_DEPENDENCY_ROOT/$package_name"
    if [[ -d "$package_path" ]]; then
      resolved_path="$(cd "$package_path" && pwd -P)"
      printf '%s=%s|%s\n' "$package_name" "$package_path" "$resolved_path"
    else
      printf '%s=%s|missing\n' "$package_name" "$package_path"
    fi
  done
}

skip_route_fingerprint() {
  skip_route_manifest | shasum -a 256 | awk '{ print $1 }'
}

SKIP_ROUTE_FINGERPRINT="$(skip_route_fingerprint)"
SKIP_RUNNER_SOURCE_FINGERPRINT="$(package_source_fingerprint "$SKIPLOCAL_RESOLVED")"

if [[ -f "$NATIVE_BUILD_CONFIG_FILE" ]]; then
  check_pinned_config_value app_root "$APP_ROOT"
  check_pinned_config_value skiplocal_resolved "$SKIPLOCAL_RESOLVED"
  check_pinned_config_value skip_dependency_root "$SKIP_DEPENDENCY_ROOT"
  check_pinned_config_value skip_dependency_root_resolved "$SKIP_DEPENDENCY_ROOT_RESOLVED"
  check_pinned_config_value skip_route_fingerprint "$SKIP_ROUTE_FINGERPRINT"
  check_pinned_config_value skip_sharing_swift_sharing_resolved "$SKIP_SHARING_SWIFT_SHARING_RESOLVED"
  if [[ "${BUILD_CONFIG_VERSION:-0}" =~ ^(5|6)$ ]]; then
    check_pinned_config_value android_package_inputs_fingerprint "$ANDROID_PACKAGE_INPUTS_FINGERPRINT"
  fi
  if [[ "${BUILD_CONFIG_VERSION:-0}" == "6" ]]; then
    check_pinned_config_value build_lane generated-gradle-fuse-app
  fi
fi

if [[ -z "$GRADLE_BIN" ]]; then
  GRADLE_BIN="$(first_executable \
    "/private/tmp/gradle-9.4.1/bin/gradle" \
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
export OME_TCA26_PATH
export OME_COMPOSABLE_NOTIFICATIONS_PATH="$COMPOSABLE_NOTIFICATIONS_PATH"
export OME_COMPOSABLE_ATMOSPHERE_TANGLED_PATH="$COMPOSABLE_ATMOSPHERE_TANGLED_PATH"
export OME_DEPENDENCIES_HTTP_CLIENT_PATH="$DEPENDENCIES_HTTP_CLIENT_PATH"
if [[ -n "$COMPOSABLE_WORKSPACE_PATH" ]]; then
  export OME_COMPOSABLE_WORKSPACE_PATH="$COMPOSABLE_WORKSPACE_PATH"
fi
if [[ -n "$ARCHITECTURES" ]]; then
  export SKIP_EXPORT_ARCHS="$ARCHITECTURES"
fi
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$SMOKE_ROOT/gradle-user-home}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$SMOKE_ROOT/clang-module-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$SMOKE_ROOT/swift-module-cache}"
export CFFIXED_USER_HOME="${CFFIXED_USER_HOME:-$SMOKE_ROOT/swiftpm-home}"
export SWIFT_SDK_HOME="${SWIFT_SDK_HOME:-${HOME}/Library/org.swift.swiftpm/swift-sdks}"
export SWIFT_ANDROID_SDK_BUNDLE="${SWIFT_ANDROID_SDK_BUNDLE:-$SWIFT_SDK_HOME/swift-6.3.3-RELEASE_android.artifactbundle}"
export SWIFT_TOOLCHAIN_DIR="${SWIFT_TOOLCHAIN_DIR:-${HOME}/Library/Developer/Toolchains}"
export OME_ANDROID_APP_BUILD="${OME_ANDROID_APP_BUILD:-1}"
if [[ -n "$OME_OPEN_MUSIC_EVENT_PATH" ]]; then
  export OME_OPEN_MUSIC_EVENT_PATH
fi
export SKIP_ANDROID_PREBUILD
if [[ "$SKIP_ANDROID_PREBUILD" == "0" ]]; then
  # The Skip-generated Gradle project otherwise invokes its native Swift build
  # from mergeDebugJniLibFolders. Reuse the already validated JNI products and
  # let Gradle do only the UI-marked wrapper packaging.
  export SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1
else
  export SKIP_BRIDGE_ANDROID_BUILD_DISABLED=0
fi
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
    "$SMOKE_ROOT/package-state" \
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

ANDROID_TEST_SCRATCH_PATH="${SKIP_SCRATCH_PATH:-$SMOKE_ROOT/skip-android-tests}"
PACKAGE_RESOLUTION_CONFIG_FILE="${OME_ANDROID_PACKAGE_RESOLUTION_CONFIG_FILE:-$SMOKE_ROOT/android-package-resolution-config}"
WORKSPACE_PACKAGE_RESOLVED="$APP_ROOT/Package.resolved"
ANDROID_PACKAGE_RESOLVED="$SMOKE_ROOT/package-state/Package.resolved"
WORKSPACE_PACKAGE_RESOLVED_BACKUP=""
WORKSPACE_PACKAGE_RESOLVED_WAS_PRESENT=0
ANDROID_PACKAGE_RESOLUTION_ACTIVE=0
ANDROID_PACKAGE_RESOLUTION_CAPTURE=0

restore_workspace_package_resolution() {
  local exit_status="$1"
  local cached_package_resolved="$ANDROID_PACKAGE_RESOLVED.next"

  trap - EXIT
  set +e

  if [[ "$ANDROID_PACKAGE_RESOLUTION_ACTIVE" -eq 1 ]]; then
    if [[ "$ANDROID_PACKAGE_RESOLUTION_CAPTURE" -eq 1 && -f "$WORKSPACE_PACKAGE_RESOLVED" ]]; then
      cp -p "$WORKSPACE_PACKAGE_RESOLVED" "$cached_package_resolved"
      mv "$cached_package_resolved" "$ANDROID_PACKAGE_RESOLVED"
    fi

    if [[ "$WORKSPACE_PACKAGE_RESOLVED_WAS_PRESENT" -eq 1 ]]; then
      cp -p "$WORKSPACE_PACKAGE_RESOLVED_BACKUP" "$WORKSPACE_PACKAGE_RESOLVED"
    else
      rm -f "$WORKSPACE_PACKAGE_RESOLVED"
    fi
    rm -f "$WORKSPACE_PACKAGE_RESOLVED_BACKUP" "$cached_package_resolved"
  fi

  exit "$exit_status"
}

prepare_android_package_resolution() {
  [[ "$DRY_RUN" -eq 0 ]] || return 0

  WORKSPACE_PACKAGE_RESOLVED_BACKUP="$(mktemp "$SMOKE_ROOT/package-state/workspace-Package.resolved.XXXXXX")"
  if [[ -f "$WORKSPACE_PACKAGE_RESOLVED" ]]; then
    WORKSPACE_PACKAGE_RESOLVED_WAS_PRESENT=1
    cp -p "$WORKSPACE_PACKAGE_RESOLVED" "$WORKSPACE_PACKAGE_RESOLVED_BACKUP"
  fi

  if [[ -f "$ANDROID_PACKAGE_RESOLVED" ]]; then
    cp -p "$ANDROID_PACKAGE_RESOLVED" "$WORKSPACE_PACKAGE_RESOLVED"
    echo "Restored workspace-specific Android package resolution"
  fi

  ANDROID_PACKAGE_RESOLUTION_ACTIVE=1
  trap 'restore_workspace_package_resolution "$?"' EXIT
}

package_resolution_config() {
  cat <<CONFIG
version=5
app_package_graph_fingerprint=$(package_graph_fingerprint "$APP_ROOT")
ome_package_graph_fingerprint=$(package_graph_fingerprint "$OME_PACKAGE_ROOT")
android_package_inputs_fingerprint=$ANDROID_PACKAGE_INPUTS_FINGERPRINT
skiplocal=$SKIPLOCAL
skip_sharing_swift_sharing=$SKIP_SHARING_SWIFT_SHARING
ome_tca26_path=$OME_TCA26_PATH
composable_notifications_path=$COMPOSABLE_NOTIFICATIONS_PATH
composable_atmosphere_tangled_path=$COMPOSABLE_ATMOSPHERE_TANGLED_PATH
composable_workspace_path=${COMPOSABLE_WORKSPACE_PATH:-remote}
dependencies_http_client_path=$DEPENDENCIES_HTTP_CLIENT_PATH
ome_android_app_build=$OME_ANDROID_APP_BUILD
CONFIG
}

invalidate_stale_package_resolution_state() {
  local workspace_state="$APP_ROOT/.build/workspace-state.json"
  local manifest_cache="$CFFIXED_USER_HOME/Library/Caches/org.swift.swiftpm/manifests/manifest.db"
  local nested_workspace_state

  if [[ -f "$PACKAGE_RESOLUTION_CONFIG_FILE" ]] \
    && cmp -s "$PACKAGE_RESOLUTION_CONFIG_FILE" <(package_resolution_config)
  then
    return 0
  fi

  if [[ -f "$workspace_state" ]]; then
    echo "Invalidating stale Android SwiftPM workspace state: $workspace_state"
    run rm -f "$workspace_state"
  fi

  # The generated Fuse build has its own SwiftPM scratch graph. Local package
  # routes can change in place without changing their path, so invalidate both
  # its resolved workspace state and SwiftPM's cached manifest evaluations.
  while IFS= read -r -d '' nested_workspace_state; do
    echo "Invalidating stale generated Android SwiftPM workspace state: $nested_workspace_state"
    run rm -f "$nested_workspace_state"
  done < <(
    find "$APP_ROOT/.build/plugins/outputs" \
      -type f \
      -path '*/destination/skipstone/*/build/swift/workspace-state.json' \
      -print0 2>/dev/null
  )

  if [[ -f "$manifest_cache" ]]; then
    echo "Invalidating stale Android SwiftPM manifest cache: $manifest_cache"
    run rm -f "$manifest_cache" "$manifest_cache-shm" "$manifest_cache-wal"
  fi
}

record_package_resolution_config() {
  if [[ "$DRY_RUN" -eq 0 ]]; then
    package_resolution_config > "$PACKAGE_RESOLUTION_CONFIG_FILE"
  fi
}

verify_swift_sdks() {
  local isolated_sdk_home="$CFFIXED_USER_HOME/Library/org.swift.swiftpm/swift-sdks"
  local sdk_link

  [[ -d "$SWIFT_SDK_HOME" ]] || fail "Swift SDK directory does not exist: $SWIFT_SDK_HOME"
  [[ -d "$SWIFT_ANDROID_SDK_BUNDLE" ]] || fail "Swift Android SDK artifact bundle does not exist: $SWIFT_ANDROID_SDK_BUNDLE"
  [[ -d "$SWIFT_TOOLCHAIN_DIR" ]] || fail "Swift toolchain directory does not exist: $SWIFT_TOOLCHAIN_DIR"
  local runtime_sdk="$SWIFT_SDK_HOME/$(basename "$SWIFT_ANDROID_SDK_BUNDLE")"
  [[ -d "$runtime_sdk" ]] || fail "Skip runtime SDK is missing: $runtime_sdk"
  [[ "$(cd "$runtime_sdk" && pwd -P)" == "$(cd "$SWIFT_ANDROID_SDK_BUNDLE" && pwd -P)" ]] \
    || fail "Skip runtime SDK and SwiftPM artifact bundle must resolve to the same SDK"

  mkdir -p "$isolated_sdk_home"
  for sdk_link in "$isolated_sdk_home"/*android*.artifactbundle; do
    [[ -L "$sdk_link" ]] || continue
    [[ "$(basename "$sdk_link")" == "$(basename "$SWIFT_ANDROID_SDK_BUNDLE")" ]] || unlink "$sdk_link"
  done
  ln -sfn "$SWIFT_ANDROID_SDK_BUNDLE" "$isolated_sdk_home/$(basename "$SWIFT_ANDROID_SDK_BUNDLE")"
}

configure_android_namespace_init_script() {
  cp "$ROOT/Scripts/android-library-namespace.init.gradle.kts" "$ANDROID_NAMESPACE_INIT_SCRIPT"
}

ensure_skip_command() {
  local rebuild=0
  local rebuild_reason=""

  if [[ "$SKIP_COMMAND_MANAGED" -eq 0 ]]; then
    [[ -x "$SKIP_COMMAND_OVERRIDE" ]] || fail "explicit SkipRunner is not executable: $SKIP_COMMAND_OVERRIDE"
    SKIP_RUNNER_STATE="external"
    return 0
  fi

  if [[ ! -x "$SKIP_COMMAND_OVERRIDE" ]]; then
    rebuild=1
    rebuild_reason="managed executable is missing"
  elif [[ ! -f "$SKIP_RUNNER_PROVENANCE_FILE" ]]; then
    rebuild=1
    rebuild_reason="managed provenance is missing"
  elif ! cmp -s "$SKIP_RUNNER_PROVENANCE_FILE" <(skip_runner_provenance); then
    rebuild=1
    rebuild_reason="managed provenance changed"
  fi

  if [[ "$rebuild" -eq 1 ]]; then
    SKIP_RUNNER_STATE="rebuild required: $rebuild_reason"
    echo "Building local SkipRunner because $rebuild_reason"
    run swift build \
      --package-path "$SKIPLOCAL" \
      --product SkipRunner \
      --scratch-path "$SKIPSTONE_BUILD_ROOT" \
      --cache-path "$SKIPSTONE_SWIFTPM_ROOT/cache" \
      --config-path "$SKIPSTONE_SWIFTPM_ROOT/config" \
      --security-path "$SKIPSTONE_SWIFTPM_ROOT/security"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      return 0
    fi
    [[ -x "$SKIP_COMMAND_OVERRIDE" ]] || fail "managed SkipRunner build did not produce: $SKIP_COMMAND_OVERRIDE"
    skip_runner_provenance > "$SKIP_RUNNER_PROVENANCE_FILE"
    SKIP_RUNNER_STATE="rebuilt and recorded"
  else
    SKIP_RUNNER_STATE="provenance matched"
  fi

  [[ -x "$SKIP_COMMAND_OVERRIDE" ]] || fail "local SkipRunner is not executable: $SKIP_COMMAND_OVERRIDE"
}

skip_runner_provenance() {
  cat <<PROVENANCE
version=1
skiplocal=$SKIPLOCAL
skiplocal_resolved=$SKIPLOCAL_RESOLVED
skip_dependency_root=$SKIP_DEPENDENCY_ROOT
skip_dependency_root_resolved=$SKIP_DEPENDENCY_ROOT_RESOLVED
skip_route_fingerprint=$SKIP_ROUTE_FINGERPRINT
source_fingerprint=$SKIP_RUNNER_SOURCE_FINGERPRINT
skip_runner=$SKIP_COMMAND_OVERRIDE
PROVENANCE
}

# Gradle daemons outlive the shell that launched them and therefore do not
# reliably inherit SKIPLOCAL. The generated Fuse build does explicitly forward
# SKIP_COMMAND_OVERRIDE, so route that command through a stable wrapper that
# restores the local toolchain selection for every nested SwiftPM invocation.
configure_nested_skip_command() {
  local skip_runner_command="$SKIP_COMMAND_OVERRIDE"
  local skip_command_wrapper="$SMOKE_ROOT/bin/SkipRunner-observation-aware"
  local quoted_android_app_build
  local quoted_skiplocal
  local quoted_skip_runner
  local quoted_skip_sharing
  local quoted_wrapper
  local quoted_architectures
  local quoted_ome_path
  local quoted_tca26_path
  local quoted_composable_notifications
  local quoted_composable_atmosphere_tangled
  local quoted_composable_workspace
  local quoted_dependencies_http_client
  local quoted_file_tree
  local quoted_clocks

  printf -v quoted_android_app_build '%q' "$OME_ANDROID_APP_BUILD"
  printf -v quoted_skiplocal '%q' "$SKIPLOCAL"
  printf -v quoted_skip_runner '%q' "$skip_runner_command"
  printf -v quoted_skip_sharing '%q' "$SKIP_SHARING_SWIFT_SHARING"
  printf -v quoted_wrapper '%q' "$skip_command_wrapper"
  printf -v quoted_tca26_path '%q' "$OME_TCA26_PATH"
  printf -v quoted_composable_notifications '%q' "$COMPOSABLE_NOTIFICATIONS_PATH"
  printf -v quoted_composable_atmosphere_tangled '%q' "$COMPOSABLE_ATMOSPHERE_TANGLED_PATH"
  printf -v quoted_dependencies_http_client '%q' "$DEPENDENCIES_HTTP_CLIENT_PATH"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
      printf 'export OME_ANDROID_APP_BUILD=%s\n' "$quoted_android_app_build"
      printf 'export SKIPLOCAL=%s\n' "$quoted_skiplocal"
      printf 'export SKIP_COMMAND_OVERRIDE=%s\n' "$quoted_wrapper"
      printf 'export SKIP_SHARING_SWIFT_SHARING=%s\n' "$quoted_skip_sharing"
      printf 'export OME_TCA26_PATH=%s\n' "$quoted_tca26_path"
      printf 'export OME_COMPOSABLE_NOTIFICATIONS_PATH=%s\n' "$quoted_composable_notifications"
      printf 'export OME_COMPOSABLE_ATMOSPHERE_TANGLED_PATH=%s\n' "$quoted_composable_atmosphere_tangled"
      printf 'export OME_DEPENDENCIES_HTTP_CLIENT_PATH=%s\n' "$quoted_dependencies_http_client"
      if [[ -n "${OME_SKIP_AUTHENTICATION_SERVICES_PATH:-}" ]]; then
        printf -v quoted_authentication_services '%q' "$OME_SKIP_AUTHENTICATION_SERVICES_PATH"
        printf 'export OME_SKIP_AUTHENTICATION_SERVICES_PATH=%s\n' "$quoted_authentication_services"
      fi
      if [[ -n "${OME_DEBUG_SNAPSHOTS_PATH:-}" ]]; then
        printf -v quoted_debug_snapshots '%q' "$OME_DEBUG_SNAPSHOTS_PATH"
        printf 'export OME_DEBUG_SNAPSHOTS_PATH=%s\n' "$quoted_debug_snapshots"
      fi
      if [[ -n "${OME_CUSTOM_DUMP_PATH:-}" ]]; then
        printf -v quoted_custom_dump '%q' "$OME_CUSTOM_DUMP_PATH"
        printf 'export OME_CUSTOM_DUMP_PATH=%s\n' "$quoted_custom_dump"
      fi
      if [[ -n "${OME_CLOCKS_PATH:-}" ]]; then
        printf -v quoted_clocks '%q' "$OME_CLOCKS_PATH"
        printf 'export OME_CLOCKS_PATH=%s\n' "$quoted_clocks"
      fi
      if [[ -n "${OME_FILE_TREE_PATH:-}" ]]; then
        printf -v quoted_file_tree '%q' "$OME_FILE_TREE_PATH"
        printf 'export OME_FILE_TREE_PATH=%s\n' "$quoted_file_tree"
      fi
      if [[ -n "$COMPOSABLE_WORKSPACE_PATH" ]]; then
        printf -v quoted_composable_workspace '%q' "$COMPOSABLE_WORKSPACE_PATH"
        printf 'export OME_COMPOSABLE_WORKSPACE_PATH=%s\n' "$quoted_composable_workspace"
      fi
      if [[ -n "$OME_OPEN_MUSIC_EVENT_PATH" ]]; then
        printf -v quoted_ome_path '%q' "$OME_OPEN_MUSIC_EVENT_PATH"
        printf 'export OME_OPEN_MUSIC_EVENT_PATH=%s\n' "$quoted_ome_path"
      fi
      if [[ -n "$ARCHITECTURES" ]]; then
        printf -v quoted_architectures '%q' "$ARCHITECTURES"
        printf 'export SKIP_EXPORT_ARCHS=%s\n' "$quoted_architectures"
      fi
      printf 'exec %s "$@"\n' "$quoted_skip_runner"
    } > "$skip_command_wrapper"
    chmod +x "$skip_command_wrapper"
  fi

  SKIP_RUNNER_COMMAND="$skip_runner_command"
  SKIP_COMMAND_OVERRIDE="$skip_command_wrapper"
  export SKIP_COMMAND_OVERRIDE
}

if [[ "$DRY_RUN" -eq 0 ]]; then
  configure_android_namespace_init_script
  verify_swift_sdks
fi
ensure_skip_command
configure_nested_skip_command

echo "Android smoke harness"
echo "  wiring repo: $ROOT"
echo "  app root:    $APP_ROOT"
echo "  OME package: ${OME_OPEN_MUSIC_EVENT_PATH:-in-app-root}"
if [[ "$RUN_TESTS" -eq 1 ]]; then
  echo "  action:      Android instrumentation tests"
else
  echo "  action:      generated Gradle/Fuse app build"
fi
echo "  configuration: $CONFIGURATION"
echo "  artifact:    $ARTIFACT"
echo "  architectures: ${ARCHITECTURES:-automatic}"
echo "  build config: $NATIVE_BUILD_CONFIG_FILE ($BUILD_CONFIG_STATE)"
echo "  skip runner: $SKIP_RUNNER_COMMAND"
echo "  runner state: $SKIP_RUNNER_STATE"
echo "  runner provenance: $SKIP_RUNNER_PROVENANCE_FILE"
echo "  runner source: $SKIP_RUNNER_SOURCE_FINGERPRINT"
echo "  nested skip: $SKIP_COMMAND_OVERRIDE"
echo "  skip build:  $SKIPSTONE_BUILD_ROOT"
echo "  SKIPLOCAL:   $SKIPLOCAL"
echo "  resolved:    $SKIPLOCAL_RESOLVED"
echo "  Skip root:   $SKIP_DEPENDENCY_ROOT"
echo "  route hash:  $SKIP_ROUTE_FINGERPRINT"
echo "  Sharing:     $SKIP_SHARING_SWIFT_SHARING"
echo "  TCA26:       $OME_TCA26_PATH"
echo "  Notifications: $COMPOSABLE_NOTIFICATIONS_PATH"
echo "  Tangled:     $COMPOSABLE_ATMOSPHERE_TANGLED_PATH"
echo "  Workspace:   ${COMPOSABLE_WORKSPACE_PATH:-remote}"
echo "  HTTP client: $DEPENDENCIES_HTTP_CLIENT_PATH"
echo "  package inputs: $ANDROID_PACKAGE_INPUTS_FINGERPRINT"
printf '%s\n' "$ANDROID_PACKAGE_INPUT_MANIFEST" | sed 's/^/    /'
echo "  namespace init: $ANDROID_NAMESPACE_INIT_SCRIPT"
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
if [[ "$RUN_TESTS" -eq 1 ]]; then
  echo "  test app APK: $ANDROID_TEST_APP_APK"
  echo "  test parallelism: $ANDROID_TEST_PARALLELISM"
  if [[ -n "$ANDROID_TEST_FILTER" ]]; then
    echo "  test filter: $ANDROID_TEST_FILTER"
  fi
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  dry run:     yes"
fi

run_compose_tests() {
  ANDROID_PACKAGE_RESOLUTION_CAPTURE=1
  local scratch="$SMOKE_ROOT/compose-host"
  local gradle_project
  run env SKIP_PLUGIN_DISABLED=0 SKIP_ACTION=none swift build \
    --package-path "$APP_ROOT" --scratch-path "$scratch" \
    --build-system native --skip-update --target SwiftUITabFeaturesFuseFixturesTests
  if [[ "$DRY_RUN" -eq 1 ]]; then
    gradle_project="$scratch/plugins/outputs/OME/SwiftUITabFeaturesFuseFixturesTests/destination/skipstone"
  else
    local projects=("$scratch"/plugins/outputs/*/SwiftUITabFeaturesFuseFixturesTests/destination/skipstone)
    [[ "${#projects[@]}" -eq 1 && -d "${projects[0]}" ]] \
      || fail "expected one generated Compose test project"
    gradle_project="${projects[0]}"
  fi
  local test_started
  test_started="$(date +%s)"
  run "$SKIP_COMMAND_OVERRIDE" gradle -p "$gradle_project" \
    --no-daemon --init-script "$ANDROID_NAMESPACE_INIT_SCRIPT" \
    :SwiftUITabFeaturesFuseFixtures:connectedDebugAndroidTest --rerun
  run python3 "$ROOT/Scripts/check-compose-test-results.py" \
    "$gradle_project/SwiftUITabFeaturesFuseFixtures/build/outputs/androidTest-results/connected/debug" \
    --since "$test_started"
}

run_android_tests() {
  [[ -f "$ANDROID_TEST_APP_APK" ]] \
    || fail "Android tests require the canonical app APK at $ANDROID_TEST_APP_APK; run Scripts/android-smoke-build.sh first"
  ANDROID_PACKAGE_RESOLUTION_CAPTURE=1
  local test_arguments=(
    android test
    --apk
    --app-apk "$ANDROID_TEST_APP_APK"
    --testing-library testing
    --maximum-parallelization-width "$ANDROID_TEST_PARALLELISM"
  )
  if [[ -n "$ANDROID_TEST_FILTER" ]]; then
    test_arguments+=(--filter "$ANDROID_TEST_FILTER")
  fi
  test_arguments+=(
    --android-serial "$ANDROID_SERIAL"
    --plain
    --package-path "$APP_ROOT"
    --scratch-path "$ANDROID_TEST_SCRATCH_PATH"
    --configuration "$CONFIGURATION"
  )
  run "$SKIP_COMMAND_OVERRIDE" "${test_arguments[@]}"
}

# SwiftPM may rewrite Package.resolved without changing its contents. Fingerprint the generated
# package graph so a timestamp-only rewrite does not invalidate the full Android SwiftUI module.
native_package_metadata_fingerprint() {
  find "$APP_ROOT/.build/plugins/outputs" \
    -type f \
    \( -name Package.swift -o -name Package.resolved \) \
    -exec shasum -a 256 {} + 2>/dev/null \
    | LC_ALL=C sort \
    | shasum -a 256 \
    | awk '{ print $1 }'
}

native_build_config() {
  cat <<CONFIG
version=6
build_lane=generated-gradle-fuse-app
app_root=$APP_ROOT
ome_open_music_event_path=${OME_OPEN_MUSIC_EVENT_PATH:-none}
ome_open_music_event_path_resolved=${OME_OPEN_MUSIC_EVENT_PATH_RESOLVED:-none}
swift_android_sdk_bundle=$SWIFT_ANDROID_SDK_BUNDLE
swift_sdk_home=$SWIFT_SDK_HOME
foundation_networking_arm64_sha256=$(shasum -a 256 "$SWIFT_ANDROID_SDK_BUNDLE/swift-android/swift-resources/usr/lib/swift-aarch64/android/libFoundationNetworking.so" | awk '{ print $1 }')
swift_toolchain_dir=$SWIFT_TOOLCHAIN_DIR
skiplocal=$SKIPLOCAL
skiplocal_resolved=$SKIPLOCAL_RESOLVED
skip_dependency_root=$SKIP_DEPENDENCY_ROOT
skip_dependency_root_resolved=$SKIP_DEPENDENCY_ROOT_RESOLVED
skip_route_fingerprint=$SKIP_ROUTE_FINGERPRINT
skip_command=$SKIP_COMMAND_OVERRIDE
skip_runner=$SKIP_RUNNER_COMMAND
skip_runner_provenance=$SKIP_RUNNER_PROVENANCE_FILE
skip_runner_source_fingerprint=$SKIP_RUNNER_SOURCE_FINGERPRINT
skip_sharing_swift_sharing=$SKIP_SHARING_SWIFT_SHARING
skip_sharing_swift_sharing_resolved=$SKIP_SHARING_SWIFT_SHARING_RESOLVED
android_package_inputs_fingerprint=$ANDROID_PACKAGE_INPUTS_FINGERPRINT
ome_android_app_build=$OME_ANDROID_APP_BUILD
configuration=$CONFIGURATION
architectures=${ARCHITECTURES:-automatic}
native_package_metadata_fingerprint=$(native_package_metadata_fingerprint)
CONFIG
}

native_package_projection_is_fresh() {
  local generated_package="$1"
  local source_package="${OME_OPEN_MUSIC_EVENT_PATH:-$APP_ROOT}/Package.swift"
  local source_size

  source_size="$(wc -c < "$source_package" | tr -d ' ')"
  cmp -s "$source_package" <(head -c "$source_size" "$generated_package")
}

native_android_dependency_projection_is_complete() {
  local generated_package="$1"
  local generated_package_root="${generated_package%/Package.swift}"

  # The Android graph replaces GRDB.swift with grdb-sqlcipher. A fresh source
  # projection can still be unusable when it was generated before SwiftPM
  # resolved that Android-only checkout, leaving the nested native build to
  # resolve both packages and fail with duplicate GRDB targets.
  [[ -f "$generated_package_root/Packages/grdb-sqlcipher/Package.swift" ]]
}

invalidate_stale_native_package_projections() {
  local generated_package
  local projection_path="*/$APP_MODULE_TARGET/destination/skipstone/$APP_MODULE_TARGET/src/main/swift/Package.swift"

  while IFS= read -r -d '' generated_package; do
    if native_package_projection_is_fresh "$generated_package" \
      && native_android_dependency_projection_is_complete "$generated_package"
    then
      continue
    fi

    if [[ "$SKIP_ANDROID_PREBUILD" == "0" ]]; then
      fail "stale or incomplete Android native Package.swift projection: $generated_package; rerun without --no-prebuild"
    fi

    echo "Invalidating stale or incomplete Android native Package.swift projection: $generated_package"
    run rm -f "$generated_package"
  done < <(
    find "$APP_ROOT/.build/plugins/outputs" \
      -type f \
      -path "$projection_path" \
      -print0 2>/dev/null
  )
}

verify_native_package_projections() {
  local generated_package
  local projection_count=0
  local projection_path="*/$APP_MODULE_TARGET/destination/skipstone/$APP_MODULE_TARGET/src/main/swift/Package.swift"

  while IFS= read -r -d '' generated_package; do
    projection_count=$((projection_count + 1))
    native_package_projection_is_fresh "$generated_package" \
      || fail "Android native Package.swift projection is stale after build: $generated_package"
    native_android_dependency_projection_is_complete "$generated_package" \
      || fail "Android native Package.swift projection is missing grdb-sqlcipher after build: $generated_package"
  done < <(
    find "$APP_ROOT/.build/plugins/outputs" \
      -type f \
      -path "$projection_path" \
      -print0 2>/dev/null
  )

  [[ "$projection_count" -gt 0 ]] || fail "no generated Android native Package.swift projection found"
  echo "Verified $projection_count current Android native Package.swift projection(s)"
}

skip_source_projection_is_fresh() {
  local sourcehash="$1"
  local target="$2"
  local source_dir="$3/Sources/$target"

  cmp -s \
    <(
      jq -r '.sourcehashes | to_entries[] | "\(.value)  \(.key)"' "$sourcehash" \
        | LC_ALL=C sort
    ) \
    <(
      (
        cd "$source_dir"
        find . \
          -type f \
          \( -name '*.swift' -o -path '*/Skip/*' \) \
          -exec shasum -a 256 {} +
      ) \
        | sed 's#  \./#  #' \
        | LC_ALL=C sort
    )
}

verify_skip_source_projections() {
  local phase="$1"
  local package_identity
  local package_root
  local projection_count=0
  local sourcehash
  local sourcehash_count
  local stale_count=0
  local target

  command -v jq >/dev/null || fail "jq is required to verify generated Android source projections"
  for package_root in "${OME_OPEN_MUSIC_EVENT_PATH:-$ROOT}" "$APP_ROOT"; do
    [[ -d "$package_root/Sources" ]] || continue
    package_identity="$(basename "$package_root")"

    while IFS= read -r -d '' sourcehash; do
      sourcehash_count="$(jq -r '.sourcehashes | length' "$sourcehash")"
      [[ "$sourcehash_count" -gt 0 ]] || continue

      target="$(basename "$(dirname "$(dirname "$(dirname "$sourcehash")")")")"
      [[ -d "$package_root/Sources/$target" ]] || continue
      projection_count=$((projection_count + 1))

      if ! skip_source_projection_is_fresh "$sourcehash" "$target" "$package_root"; then
        echo "error: generated Android source projection is stale or incomplete for: $package_root/Sources/$target" >&2
        stale_count=$((stale_count + 1))
      fi
    done < <(
      find "$APP_ROOT/.build/plugins/outputs" \
        -mindepth 5 \
        -maxdepth 5 \
        -type f \
        -path "*/$package_identity/*/destination/skipstone/.*.sourcehash" \
        -print0 2>/dev/null
    )

    [[ "$APP_ROOT" != "$package_root" ]] || break
  done

  if [[ "$projection_count" -eq 0 ]]; then
    if [[ "$phase" == "before" && "$SKIP_ANDROID_PREBUILD" != "0" ]]; then
      echo "No generated Android source projections found; the required prebuild must create them"
      return 0
    fi
    fail "no generated Android source projections found for $APP_MODULE_TARGET"
  fi

  if [[ "$stale_count" -gt 0 ]]; then
    if [[ "$phase" == "before" && "$SKIP_ANDROID_PREBUILD" != "0" ]]; then
      echo "Detected $stale_count stale Android source projection(s); the required prebuild must refresh them"
      return 0
    fi
    fail "$stale_count generated Android source projection(s) are stale; rerun without --no-prebuild"
  fi

  echo "Verified $projection_count current Android source projection(s)"
}

# A stale compatibility module makes unrelated packages' canImport(SwiftUI)
# branches depend on incremental build order, exposing undeclared CJNI or MachO imports.
invalidate_stale_swiftui_modules() {
  local metadata
  local module
  local should_invalidate
  # Without a recorded configuration, existing SwiftUI metadata has no trustworthy
  # package-route provenance. Treat it as stale just as we do a changed configuration.
  local config_changed=1

  if [[ -f "$NATIVE_BUILD_CONFIG_FILE" ]]; then
    config_changed=0
    if ! cmp -s "$NATIVE_BUILD_CONFIG_FILE" <(native_build_config); then
      config_changed=1
    fi
  fi

  while IFS= read -r -d '' module; do
    should_invalidate="$config_changed"
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
      -path "*/build/swift/*-unknown-linux-android*/$CONFIGURATION/Modules/SwiftUI.swiftmodule" \
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

verify_root_constructor_bridges() {
  local bridge
  local bridge_count=0
  local failure_count=0
  local sources_file

  while IFS= read -r -d '' sources_file; do
    while IFS= read -r bridge; do
      case "$bridge" in
        */SkipBridgeGenerated/OpenMusicEventApp_Bridge.swift)
          bridge_count=$((bridge_count + 1))
          if ! rg -Fq '@_cdecl("Java_open_music_event_app_OpenMusicEventApplicationRootView_Swift_1constructor_10")' "$bridge"; then
            echo "error: compiled OME bridge does not export the generic root constructor: $bridge" >&2
            failure_count=$((failure_count + 1))
          fi
          ;;
      esac
    done < "$sources_file"
  done < <(
    find "$APP_ROOT/.build/plugins/outputs" \
      -type f \
      -path "*/build/swift/*-unknown-linux-android*/$CONFIGURATION/OpenMusicEventApp.build/sources" \
      -print0 2>/dev/null
  )

  [[ "$bridge_count" -gt 0 ]] || fail "no compiled OpenMusicEventApp bridge source found under $APP_ROOT/.build/plugins/outputs"
  [[ "$failure_count" -eq 0 ]] || fail "$failure_count compiled OME root bridge(s) omitted the generic constructor"
  echo "Verified $bridge_count compiled generic OME root constructor bridge(s)"
}

invalidate_stale_observation_bridges() {
  local bridge

  while IFS= read -r -d '' bridge; do
    rg -q 'withObservationTracking' "$bridge" && continue

    if [[ "$SKIP_ANDROID_PREBUILD" == "0" ]]; then
      fail "stale generated OME observation bridge: $bridge; rerun without --no-prebuild"
    fi

    echo "Invalidating stale generated OME observation bridge: $bridge"
    run rm -f "$bridge"
  done < <(
    find "$APP_ROOT/.build/plugins/outputs" \
      -type f \
      -path '*/SkipBridgeGenerated/OpenMusicEventAppRoot_Bridge.swift' \
      -print0 2>/dev/null
  )
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

build_app() {
  local -a build_command
  local gradle_task

  ANDROID_PACKAGE_RESOLUTION_CAPTURE=1
  invalidate_stale_native_package_projections
  verify_skip_source_projections before
  invalidate_stale_observation_bridges
  invalidate_stale_swiftui_modules
  if [[ "$SKIP_ANDROID_PREBUILD" == "0" && "$DRY_RUN" == "0" ]]; then
    local reusable_native_product
    reusable_native_product="$({
      find "$APP_ROOT/.build/plugins/outputs" \
        -type f \
        -path '*/OpenMusicEventApp/build/jni-libs/*/libOpenMusicEventApp.so' \
        -print -quit 2>/dev/null
    } || true)"
    [[ -n "$reusable_native_product" ]] \
      || fail "--no-prebuild requires a validated libOpenMusicEventApp.so; run once without --no-prebuild"
    echo "Reusing validated Android native product: $reusable_native_product"
  fi
  if [[ "$ARTIFACT" == "bundle" ]]; then
    gradle_task=":app:bundle$CONFIGURATION_SUFFIX"
  else
    gradle_task=":app:assemble$CONFIGURATION_SUFFIX"
  fi
  build_command=(
    "$SKIP_COMMAND_OVERRIDE" gradle
    -p "$APP_ROOT/Android"
    --no-daemon
    --init-script "$ANDROID_NAMESPACE_INIT_SCRIPT"
    "$gradle_task"
  )
  [[ "${build_command[1]}" == "gradle" ]] \
    || fail "Android app builds must invoke Skip Gradle"
  [[ "${build_command[2]}" == "-p" && "${build_command[3]}" == "$APP_ROOT/Android" ]] \
    || fail "Android app builds must use the generated app Gradle project"
  [[ "${build_command[7]}" == ":app:assemble$CONFIGURATION_SUFFIX" || "${build_command[7]}" == ":app:bundle$CONFIGURATION_SUFFIX" ]] \
    || fail "Android app builds must produce an APK or AAB from the app target"

  echo "Verified canonical generated Gradle/Fuse app build command"
  run "${build_command[@]}"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    verify_native_package_projections
    verify_skip_source_projections after
    verify_observation_bridges
    verify_root_constructor_bridges
    verify_periodic_timeline_bridges
  fi
  record_native_build_config
}

apk_path() {
  local output_dir

  for output_dir in \
    "$APP_ROOT/.build/Android/app/outputs/apk/$CONFIGURATION" \
    "$APP_ROOT/Android/app/build/outputs/apk/$CONFIGURATION"
  do
    [[ -d "$output_dir" ]] || continue
    find "$output_dir" -type f -name '*.apk' -print
  done | sort | tail -n 1
}

bundle_path() {
  local output_dir

  for output_dir in \
    "$APP_ROOT/.build/Android/app/outputs/bundle/$CONFIGURATION" \
    "$APP_ROOT/Android/app/build/outputs/bundle/$CONFIGURATION"
  do
    [[ -d "$output_dir" ]] || continue
    find "$output_dir" -type f -name '*.aab' -print
  done | sort | tail -n 1
}

artifact_path() {
  if [[ "$ARTIFACT" == "bundle" ]]; then
    bundle_path
  else
    apk_path
  fi
}

prepare_android_package_resolution
invalidate_stale_package_resolution_state

if [[ "$RUN_COMPOSE_TESTS" -eq 1 ]]; then
  run_compose_tests
elif [[ "$RUN_TESTS" -eq 1 ]]; then
  run_android_tests
else
  build_app
fi

record_package_resolution_config

if [[ "$DRY_RUN" -eq 0 && "$RUN_TESTS" -eq 0 ]]; then
  ARTIFACT_PATH="$(artifact_path)"
  [[ -n "$ARTIFACT_PATH" ]] || fail "no $CONFIGURATION $ARTIFACT artifact found"
  echo "Android artifact: $ARTIFACT_PATH"
  run python3 -B "$ROOT/Scripts/verify-android-runtime.py" "$ARTIFACT_PATH" "$SWIFT_ANDROID_SDK_BUNDLE"
fi

if [[ "$DRY_RUN" -eq 0 && ( "$INSTALL" -eq 1 || "$LOGS" -eq 1 ) ]]; then
  command -v adb >/dev/null || fail "adb is not on PATH"
fi

if [[ "$INSTALL" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    APK_PATH="$APP_ROOT/.build/Android/app/outputs/apk/$CONFIGURATION/app-$CONFIGURATION.apk"
  else
    APK_PATH="$(artifact_path)"
    [[ -n "$APK_PATH" ]] || fail "no $CONFIGURATION APK found"
  fi
  run adb -s "$ANDROID_SERIAL" install -r "$APK_PATH"
fi

if [[ "$CLEAR_DATA" -eq 1 ]]; then
  run adb -s "$ANDROID_SERIAL" shell pm clear "$ANDROID_APPLICATION_ID"
fi

if [[ "$LAUNCH" -eq 1 ]]; then
  run adb -s "$ANDROID_SERIAL" shell am force-stop "$ANDROID_APPLICATION_ID"
  launch_android_app
fi

if [[ "$LOGS" -eq 1 ]]; then
  LOGCAT_FILTERS="${LOGCAT_FILTERS:-$ANDROID_APPLICATION_ID/OpenMusicEventApp OpenMusicEvent AndroidRuntime SwiftRuntime skip.ui.SkipUI}"
  # shellcheck disable=SC2086
  run adb -s "$ANDROID_SERIAL" logcat -d -v time -s $LOGCAT_FILTERS
fi
