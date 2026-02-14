#!/usr/bin/env bash
set -euo pipefail

# Build helper for desktop Debug build
# Usage: build_desktop_debug.sh [--qt-dir <qt-path>] [--clean] [--force] [-j N]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"
mkdir -p "$ARTIFACTS_DIR"

# Defaults
QT_DIR="${QT_DIR:-$HOME/Qt/*}"
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
if [[ JOBS -gt 8 ]]; then
  JOBS=8
fi

BUILD_DIR="$REPO_ROOT/build-desktop-debug"
CMAKE_BUILD_DIR="$BUILD_DIR/cmake-build"

FORCE=false
CLEAN=false

print_help() {
  cat <<EOF
Usage: $0 [options]
Options:
  --qt-dir <path>     Qt installation directory or glob (default: $QT_DIR)
  --clean             Remove previous build artifacts
  --force             Force rebuild even if binary exists
  -j|--jobs <n>       Parallel build jobs (default: $JOBS)
  -h|--help           Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --qt-dir) QT_DIR="$2"; shift 2;;
    --clean) CLEAN=true; shift;;
    --force) FORCE=true; shift;;
    -j|--jobs) JOBS="$2"; shift 2;;
    -h|--help) print_help; exit 0;;
    *) echo "Unknown argument: $1"; print_help; exit 1;;
  esac
done

# If a previous binary exists and user didn't request force, return its path
LAST_BIN_CAND="$BUILD_DIR/last_binary.txt"
if [ -f "$LAST_BIN_CAND" ] && [ "$FORCE" = false ]; then
  last_bin="$(cat "$LAST_BIN_CAND")"
  if [ -n "$last_bin" ] && [ -e "$last_bin" ]; then
    echo "$last_bin"
    exit 0
  fi
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

# Expand a glob default like $HOME/Qt/* to the newest installed kit
if [[ "$QT_DIR" == *'*'* ]] || [ ! -d "$QT_DIR" ]; then
  shopt -s nullglob
  _qt_matches=( $QT_DIR )
  shopt -u nullglob
  if [ ${#_qt_matches[@]} -gt 0 ]; then
    _candidates=()
    for _m in "${_qt_matches[@]}"; do
      if [ -f "$_m/lib/cmake/Qt6Config.cmake" ] || [ -d "$_m/lib/cmake/Qt6" ]; then
        _candidates+=( "$_m" )
      fi
    done
    if [ ${#_candidates[@]} -gt 0 ]; then
      QT_DIR=$(printf "%s\n" "${_candidates[@]}" | sort -V | tail -n1)
    else
      QT_DIR=$(printf "%s\n" "${_qt_matches[@]}" | sort -V | tail -n1)
    fi
  fi
fi

# Quick pre-check: ensure Qt6 CorePrivate is available somewhere sensible. CMake
# requires Qt6::CorePrivate in this project. If it's missing, surface a helpful
# error early instead of running CMake configure which produces a less obvious
# message.
found_coreprivate=false
qt_coreprivate_path=""
if [ -d "$QT_DIR" ]; then
  # common locations inside a Qt install
  for p in "$QT_DIR/lib/cmake/Qt6CorePrivate/Qt6CorePrivateConfig.cmake" \
           "$QT_DIR/lib/cmake/Qt6/Qt6CorePrivateConfig.cmake" \
           "$QT_DIR/lib/cmake/Qt6CorePrivateConfig.cmake"; do
    if [ -f "$p" ]; then
      found_coreprivate=true
      qt_coreprivate_path="$p"
      break
    fi
  done
fi

if [ "$found_coreprivate" = false ]; then
  # If QT_DIR points at a parent (~ /home/user/Qt) try to locate a kit
  # underneath it (eg. ~/Qt/6.x.y/gcc_64) that contains the private module.
  if [ -d "$QT_DIR" ]; then
    qt_local_match=$(find "$QT_DIR" -maxdepth 6 -type f -name 'Qt6CorePrivateConfig.cmake' -print -quit 2>/dev/null || true)
    if [ -n "$qt_local_match" ]; then
      found_coreprivate=true
      qt_coreprivate_path="$qt_local_match"
      # derive kit root (strip .../lib/cmake/Qt6CorePrivate/Qt6CorePrivateConfig.cmake)
      kit_root="$(dirname "$(dirname "$(dirname "$(dirname "$qt_local_match")")")")"
      QT_DIR="$kit_root"
    fi
  fi

  # Search common system prefixes for Qt6CorePrivateConfig.cmake. Keep the
  # search shallow to avoid long delays in large filesystems.
  sys_match=$(find /usr /opt "$HOME" -maxdepth 6 -type f -name 'Qt6CorePrivateConfig.cmake' -print -quit 2>/dev/null || true)
  if [ -n "$sys_match" ]; then
    found_coreprivate=true
    qt_coreprivate_path="$sys_match"
  fi
fi

if [ "$found_coreprivate" = false ]; then
  cat <<EOF >&2
ERROR: Qt6 private module 'Qt6::CorePrivate' not found.

CMakeLists requires Qt6 CorePrivate but no suitable Qt installation with
Qt6CorePrivate was detected. Common fixes:

- Install a full Qt development kit that includes private modules (use the
  official Qt installer or your distribution's Qt development packages).
- Or pass --qt-dir pointing to a Qt installation that contains private
  components, e.g. --qt-dir ~/Qt/6.x.y/gcc_64

If you already have a Qt installation, point the script at it with
  ./myscripts/build_desktop_debug.sh --qt-dir /path/to/Qt

The CMake configure log is at: $ARTIFACTS_DIR/cmake_config_desktop.log
EOF
  exit 2
fi

echo "Using Qt dir: ${QT_DIR:-<system>} (CorePrivate: $qt_coreprivate_path)"

cmake_args=(
  -S "$REPO_ROOT"
  -B "$CMAKE_BUILD_DIR"
  -G "$GENERATOR"
  -DCMAKE_BUILD_TYPE=Debug
)

if [ -n "$QT_DIR" ] && [ -d "$QT_DIR" ]; then
  if [ -d "$QT_DIR/lib/cmake" ]; then
    cmake_args+=( -DCMAKE_PREFIX_PATH="$QT_DIR/lib/cmake${CMAKE_PREFIX_PATH:+;$CMAKE_PREFIX_PATH}" -DQt6_DIR="$QT_DIR/lib/cmake" )
  else
    cmake_args+=( -DQt6_DIR="$QT_DIR" )
  fi
fi

echo "Configuring CMake..." | tee "$ARTIFACTS_DIR/cmake_config_desktop.log"
if ! cmake "${cmake_args[@]}" >> "$ARTIFACTS_DIR/cmake_config_desktop.log" 2>&1; then
  echo "CMake configure failed. See $ARTIFACTS_DIR/cmake_config_desktop.log" >&2
  exit 2
fi

echo "Building project..." | tee "$ARTIFACTS_DIR/cmake_build_desktop.log"
if ! cmake --build "$CMAKE_BUILD_DIR" -- -j"$JOBS" >> "$ARTIFACTS_DIR/cmake_build_desktop.log" 2>&1; then
  echo "CMake build failed. See $ARTIFACTS_DIR/cmake_build_desktop.log" >&2
  exit 3
fi

# Locate produced binary or bundle
echo "Locating build artifact..."
artifact=""

# Prefer macOS .app bundles
artifact=$(find "$BUILD_DIR" -type d -name "*.app" -print -quit 2>/dev/null || true)
if [ -z "$artifact" ]; then
  # Look for executable named wingout (case-insensitive)
  artifact=$(find "$BUILD_DIR" -type f -executable -iname "wingout" -print -quit 2>/dev/null || true)
fi
if [ -z "$artifact" ]; then
  # Fallbacks: .exe, any file named WingOut
  artifact=$(find "$BUILD_DIR" -type f -iname "wingout.exe" -print -quit 2>/dev/null || true)
fi
if [ -z "$artifact" ]; then
  artifact=$(find "$BUILD_DIR" -type f -iname "wingout*" -print -quit 2>/dev/null || true)
fi

if [ -z "$artifact" ]; then
  echo "No built desktop artifact found under $BUILD_DIR" >&2
  echo "Last lines of build log:" >&2
  tail -n 200 "$ARTIFACTS_DIR/cmake_build_desktop.log" >&2 || true
  exit 4
fi

echo "$artifact" | tee "$BUILD_DIR/last_binary.txt"
exit 0
