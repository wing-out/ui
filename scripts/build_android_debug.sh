#!/usr/bin/env bash
set -euo pipefail

# Build helper for Android debug APK
# Usage: build_android_debug.sh [--abi <abi>] [--ndk <ndk-path>] [--sdk <sdk-path>] [--qt-dir <qt-android-dir>] [--clean] [--force]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"
mkdir -p "$ARTIFACTS_DIR"

# Defaults (override via env or CLI)
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-}"
# Allow a glob default so we pick the latest installed Qt Android kit automatically
QT_ANDROID_DIR="${QT_ANDROID_DIR:-$HOME/Qt/*/android_arm64_v8a}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-31}"
JOBS="$(nproc 2>/dev/null || echo 2)"
if [ "$JOBS" -gt 4 ]; then JOBS=4; fi

BUILD_DIR="$REPO_ROOT/build-android-debug"
CMAKE_BUILD_DIR="$BUILD_DIR/android-build"

FORCE=false
CLEAN=false

print_help() {
  cat <<EOF
Usage: $0 [options]
Options:
  --abi <abi>         Android ABI (default: $ANDROID_ABI)
  --ndk <path>        Android NDK path (default: autodetect from SDK if present)
  --sdk <path>        Android SDK path (default: $ANDROID_SDK_ROOT)
  --qt-dir <path>     Qt Android kit path (optional)
  --clean             Remove previous build artifacts
  --force             Force rebuild even if APK exists
  -j|--jobs <n>       Parallel build jobs (default: $JOBS)
  -h|--help           Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --abi) ANDROID_ABI="$2"; shift 2;;
    --ndk) ANDROID_NDK_ROOT="$2"; shift 2;;
    --sdk) ANDROID_SDK_ROOT="$2"; shift 2;;
    --qt-dir) QT_ANDROID_DIR="$2"; shift 2;;
    --clean) CLEAN=true; shift ;;
    --force) FORCE=true; shift ;;
    -j|--jobs) JOBS="$2"; shift 2;;
    -h|--help) print_help; exit 0;;
    *) echo "Unknown argument: $1"; print_help; exit 1;;
  esac
done

# If NDK not provided, try to pick the latest installed inside SDK
if [ -z "$ANDROID_NDK_ROOT" ] && [ -d "$ANDROID_SDK_ROOT/ndk" ]; then
  # choose newest-looking directory
  ANDROID_NDK_ROOT="$(ls -1d "$ANDROID_SDK_ROOT/ndk"/* 2>/dev/null | sort -V | tail -n1 || true)"
fi

echo "Android SDK: $ANDROID_SDK_ROOT"
echo "Android NDK: ${ANDROID_NDK_ROOT:-<not set>}"
echo "Qt Android dir: ${QT_ANDROID_DIR:-<not set>}"
echo "Target ABI: $ANDROID_ABI"

# Export Android SDK/NDK for CMake and Qt CMake helpers which read them from the
# environment (CMake only picks up env vars when they're exported).
export ANDROID_SDK_ROOT
export ANDROID_HOME="$ANDROID_SDK_ROOT"
if [ -n "$ANDROID_NDK_ROOT" ]; then
  export ANDROID_NDK_ROOT
fi

APK_CAND="$BUILD_DIR/android-build/build/outputs/apk/debug/android-build-debug.apk"
if [ -f "$APK_CAND" ] && [ "$FORCE" = false ]; then
  echo "$APK_CAND"
  exit 0
fi

if [ "$CLEAN" = true ]; then
  echo "Removing previous build dir: $BUILD_DIR"
  rm -rf "$BUILD_DIR"
fi

mkdir -p "$CMAKE_BUILD_DIR"

# pick generator
if command -v ninja >/dev/null 2>&1; then
  GENERATOR="Ninja"
else
  GENERATOR="Unix Makefiles"
fi

# Build CMake configure command
cmake_args=(
  -S "$REPO_ROOT"
  -B "$CMAKE_BUILD_DIR"
  -G "$GENERATOR"
  -DANDROID_ABI="$ANDROID_ABI"
  -DANDROID_PLATFORM="$ANDROID_PLATFORM"
  -DCMAKE_BUILD_TYPE=Debug
  -DCMAKE_UNITY_BUILD=ON
)

if [ -n "$ANDROID_NDK_ROOT" ]; then
  cmake_args+=( -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" -DANDROID_NDK="$ANDROID_NDK_ROOT" -DCMAKE_ANDROID_NDK="$ANDROID_NDK_ROOT" )
  # When cross-compiling with the Android NDK, avoid searching the sysroot for
  # package config files — that causes CMake to prepend the sysroot to
  # CMAKE_PREFIX_PATH and prevents finding Qt installed on the host.
  cmake_args+=( -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=NEVER )
fi

# Pass the SDK path explicitly to CMake (Qt Android macros read this)
if [ -n "$ANDROID_SDK_ROOT" ]; then
  # Qt's Android CMake macros read the CMake variables ANDROID_SDK_ROOT
  # (they do not necessarily pick them from the environment), so pass them explicitly
  # as CMake variables in addition to CMAKE_ANDROID_SDK.
  cmake_args+=( -DCMAKE_ANDROID_SDK="$ANDROID_SDK_ROOT" -DANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" )
fi

# Expand a glob default like $HOME/Qt/*/android_arm64_v8a to the newest installed kit
# Expand a glob default like $HOME/Qt/*/android_arm64_v8a to the best available Qt Android kit
if [[ "$QT_ANDROID_DIR" == *'*'* ]] || [ ! -d "$QT_ANDROID_DIR" ]; then
  shopt -s nullglob
  _qt_matches=( $QT_ANDROID_DIR )
  shopt -u nullglob
  if [ ${#_qt_matches[@]} -gt 0 ]; then
    # Prefer kits that contain Qt CMake package files
    _candidates=()
    for _m in "${_qt_matches[@]}"; do
      if [ -f "$_m/lib/cmake/Qt6Config.cmake" ] || [ -d "$_m/lib/cmake/Qt6" ]; then
        _candidates+=( "$_m" )
      fi
    done
    if [ ${#_candidates[@]} -gt 0 ]; then
      QT_ANDROID_DIR=$(printf "%s\n" "${_candidates[@]}" | sort -V | tail -n1)
    else
      QT_ANDROID_DIR=$(printf "%s\n" "${_qt_matches[@]}" | sort -V | tail -n1)
    fi
  fi
fi

if [ -n "$QT_ANDROID_DIR" ] && [ -d "$QT_ANDROID_DIR" ]; then
  if [ -d "$QT_ANDROID_DIR/lib/cmake" ]; then
    # Add Qt's CMake dir to CMAKE_PREFIX_PATH so find_package(Qt6 ...) works
    cmake_args+=( -DCMAKE_PREFIX_PATH="$QT_ANDROID_DIR/lib/cmake${CMAKE_PREFIX_PATH:+;$CMAKE_PREFIX_PATH}" -DQt6_DIR="$QT_ANDROID_DIR/lib/cmake" )
  else
    cmake_args+=( -DQT_ANDROID_DIR="$QT_ANDROID_DIR" )
  fi
fi

echo "Configuring CMake..."
if ! cmake "${cmake_args[@]}" 2>&1 | tee "$ARTIFACTS_DIR/cmake_config.log"; then
  echo "CMake configure failed. See $ARTIFACTS_DIR/cmake_config.log" >&2
  exit 2
fi

echo "Building project..."
if ! cmake --build "$CMAKE_BUILD_DIR" -- -j"$JOBS" 2>&1 | tee "$ARTIFACTS_DIR/cmake_build.log"; then
  echo "CMake build failed. See $ARTIFACTS_DIR/cmake_build.log" >&2
  exit 3
fi

# Locate APK
echo "Locating APK..."
apk_path=""
apk_path=$(find "$BUILD_DIR" -type f -name "*.apk" -print -quit || true)
if [ -z "$apk_path" ]; then
  echo "No APK found in $BUILD_DIR after build." >&2
  echo "Last lines of build log:" >&2
  tail -n 200 "$ARTIFACTS_DIR/cmake_build.log" >&2 || true
  exit 4
fi

echo "$apk_path" | tee "$BUILD_DIR/last_apk.txt"
exit 0
