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
#   2. Builds every tst_* test target and QML module plugins.
#   3. Runs them via ctest (filter ^tst_) with QT_QPA_PLATFORM=offscreen.
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

# ---- Build test targets and QML module plugins ----
#
# Discover tst_* targets dynamically rather than hardcoding names. Without
# this, adding a new tst_* via tests/CMakeLists.txt would silently NOT be
# built — ctest would then fail with "Could not find executable" even
# though the registration succeeded. The previous incarnation of this
# script hardcoded `tst_wingout` (and later added a second hand-maintained
# line for tst_streaming_settings_controller_reconcile); enumerating from
# the configured CMake API keeps every future tst_* in the runner without
# manual edits.
#
# Strategy: parse the CTest registration file (built by `add_test(NAME …)`).
# Test names are also the executable target names by convention here.
echo "==> Discovering tst_* targets …"
TEST_TARGETS=()
if [ -f "$BUILD_DIR/tests/CTestTestfile.cmake" ]; then
  while IFS= read -r name; do
    [ -n "$name" ] && TEST_TARGETS+=("$name")
  done < <(
    grep -hE '^add_test\(tst_[A-Za-z0-9_]+ ' "$BUILD_DIR/tests/CTestTestfile.cmake" \
      | sed -E 's/^add_test\((tst_[A-Za-z0-9_]+) .*/\1/' \
      | sort -u
  )
fi
if [ "${#TEST_TARGETS[@]}" -eq 0 ]; then
  # Fallback: if CTest registration is not yet generated, use the current
  # roster. This keeps the script working on first-config runs.
  TEST_TARGETS=(tst_wingout tst_streaming_settings_controller_reconcile)
fi
echo "    Targets: ${TEST_TARGETS[*]}"

echo "==> Building tst_* targets and QML plugins …"
for t in "${TEST_TARGETS[@]}"; do
  # tst_qml_wrapper_pattern is a script-driven add_test (no executable
  # target to build). Skip the build step but still let ctest run it.
  if [ "$t" = "tst_qml_wrapper_pattern" ]; then
    continue
  fi
  cmake --build "$BUILD_DIR" --target "$t" -- -j"$JOBS" 2>&1 | tail -30
done
cmake --build "$BUILD_DIR" --target qt_internal_plugins -- -j"$JOBS" 2>&1 | tail -10

# ---- Run tests headlessly ----
echo "==> Running headless tests …"
export QT_QPA_PLATFORM=offscreen
export QT_QUICK_BACKEND=software
export LD_LIBRARY_PATH="${QT_DIR}/lib:${LD_LIBRARY_PATH:-}"

cd "$BUILD_DIR"
# Filter "^tst_" matches every tst_* test executable registered via
# add_test(NAME tst_*). The previous filter was "tst_wingout" which silently
# skipped tst_streaming_settings_controller_reconcile.
ctest --output-on-failure -R '^tst_' --timeout 120
echo "==> All tests passed."
