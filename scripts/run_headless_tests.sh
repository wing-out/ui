#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# run_headless_tests.sh – Build and run the WingOut headless QML test suite.
#
# Usage:
#   ./scripts/run_headless_tests.sh [--qt-dir <path>] [--clean] [-j N]
#
# The script:
#   1. Configures a CMake build (reusing the desktop build infrastructure).
#   2. Builds the test target (tst_wingout) and QML module plugins.
#   3. Runs it via ctest with QT_QPA_PLATFORM=offscreen.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build-test"

# Defaults
QT_DIR="${QT_DIR:-}"
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
[ "$JOBS" -gt 8 ] && JOBS=8

CLEAN=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --qt-dir) QT_DIR="$2"; shift 2;;
    --clean)  CLEAN=true; shift;;
    -j|--jobs) JOBS="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 [--qt-dir <path>] [--clean] [-j N]"
      exit 0;;
    *) echo "Unknown argument: $1"; exit 1;;
  esac
done

# ---- Resolve Qt path ----
if [ -z "$QT_DIR" ]; then
  # Auto-detect: find the latest Qt with gcc_64 under ~/Qt
  shopt -s nullglob
  _qt_matches=( "$HOME/Qt"/*/gcc_64 )
  shopt -u nullglob
  if [ ${#_qt_matches[@]} -gt 0 ]; then
    # Pick the one with the most cmake modules (fullest install)
    best=""
    best_count=0
    for _m in "${_qt_matches[@]}"; do
      if [ -d "$_m/lib/cmake" ]; then
        count=$(ls "$_m/lib/cmake/" 2>/dev/null | wc -l)
        if [ "$count" -gt "$best_count" ]; then
          best="$_m"
          best_count="$count"
        fi
      fi
    done
    QT_DIR="${best:-${_qt_matches[-1]}}"
  fi
fi

if [ -z "$QT_DIR" ] || [ ! -d "$QT_DIR" ]; then
  echo "ERROR: Could not find Qt installation. Use --qt-dir <path> or set QT_DIR."
  echo "  Expected: ~/Qt/<version>/gcc_64"
  exit 1
fi

echo "==> Using Qt: ${QT_DIR}"

# ---- Clean if requested ----
if [ "$CLEAN" = true ]; then
  echo "==> Cleaning build directory"
  rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

# ---- Pick generator ----
if command -v ninja >/dev/null 2>&1; then
  GENERATOR="Ninja"
else
  GENERATOR="Unix Makefiles"
fi

# ---- Configure ----
cmake_args=(
  -S "$REPO_ROOT"
  -B "$BUILD_DIR"
  -G "$GENERATOR"
  -DCMAKE_BUILD_TYPE=Debug
  -DCMAKE_PREFIX_PATH="$QT_DIR"
)

echo "==> Configuring CMake …"
cmake "${cmake_args[@]}" 2>&1 | tail -20

# ---- Build test target and QML module plugins ----
echo "==> Building tst_wingout and QML plugins …"
cmake --build "$BUILD_DIR" --target tst_wingout -- -j"$JOBS" 2>&1 | tail -30
cmake --build "$BUILD_DIR" --target qt_internal_plugins -- -j"$JOBS" 2>&1 | tail -10

# ---- Run tests headlessly ----
echo "==> Running headless tests …"
export QT_QPA_PLATFORM=offscreen
export QT_QUICK_BACKEND=software
export LD_LIBRARY_PATH="${QT_DIR}/lib:${LD_LIBRARY_PATH:-}"

cd "$BUILD_DIR"
ctest --output-on-failure -R tst_wingout --timeout 120
echo "==> All tests passed."
