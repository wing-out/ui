#!/usr/bin/env bash
set -euo pipefail

# Usage: smoke_run_wingout.sh [--package com.example.app] [--activity .MainActivity] <apk-path> [artifacts-dir]

PACKAGE_OVERRIDE=""
ACTIVITY_OVERRIDE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package)
      PACKAGE_OVERRIDE="$2"; shift 2 ;;
    --activity)
      ACTIVITY_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--package com.example.app] [--activity .MainActivity] <apk-path> [artifacts-dir]"; exit 0 ;;
    --*)
      echo "Unknown option: $1"; exit 1 ;;
    *)
      break ;;
  esac
done

APK_PATH="${1:-}"
ARTIFACTS_DIR="${2:-./artifacts}"

if [ -z "$APK_PATH" ]; then
  echo "Usage: $0 [--package com.example.app] [--activity .MainActivity] <apk-path> [artifacts-dir]"
  exit 2
fi

mkdir -p "$ARTIFACTS_DIR"

# Determine package name
PACKAGE="${PACKAGE_OVERRIDE:-}"
if [ -z "$PACKAGE" ]; then
  if command -v aapt >/dev/null 2>&1; then
    PACKAGE=$(aapt dump badging "$APK_PATH" 2>/dev/null | awk -F"'" '/package: name=/ {print $2; exit}') || true
  fi
fi
if [ -z "$PACKAGE" ]; then
  # fallback conservative default used in this repo
  PACKAGE="center.dx.wingout"
fi

# Activity
MAIN_ACTIVITY="${ACTIVITY_OVERRIDE:-.MainActivity}"

# Find adb
ADB="$(command -v adb || true)"
if [ -z "$ADB" ]; then
  ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
fi
if [ -z "$ADB" ]; then
  ADB="adb"
fi

echo "Using adb: $ADB"

echo "Starting activity $PACKAGE/$MAIN_ACTIVITY"
$ADB shell am start -n "$PACKAGE/$MAIN_ACTIVITY" > "$ARTIFACTS_DIR/adb_am_start.txt" 2>&1 || true
sleep 3

PID=$($ADB shell pidof "$PACKAGE" 2>/dev/null || echo "")
if [ -z "$PID" ]; then
  echo "App process not found. Dumping logcat"
  $ADB logcat -d > "$ARTIFACTS_DIR/logcat.txt" 2>&1 || true
  echo "Smoke test: FAILED"
  exit 3
fi

echo "App running with pid: $PID"

echo "Capturing screenshot"
$ADB exec-out screencap -p > "$ARTIFACTS_DIR/screen.png" || true

echo "Dumping logcat (last 2000 lines)"
$ADB logcat -d -t 2000 > "$ARTIFACTS_DIR/logcat.txt" || true

echo "Smoke test: OK"
exit 0
