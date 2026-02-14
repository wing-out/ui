#!/usr/bin/env bash
set -euo pipefail

# Orchestrator: create/boot emulator, build APK, install, run smoke tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$REPO_ROOT/artifacts}"
mkdir -p "$ARTIFACTS_DIR"

# CLI flags
SKIP_BUILD=false
SKIP_BOOT=false
APK_OVERRIDE=""
# If set, will force a fresh emulator instance (wipe data) when starting
FRESH_EMULATOR=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD=true; shift ;;
  --skip-boot)
      SKIP_BOOT=true; shift ;;
    --fresh)
      # Start emulator from a fresh state (wipe-data). Useful for fully repeatable runs.
      FRESH_EMULATOR=true; shift ;;
    --apk)
      APK_OVERRIDE="$2"; SKIP_BUILD=true; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--skip-build] [--skip-boot] [--fresh] [--apk /path/to/app.apk]";
      exit 0 ;;
    *)
      echo "Unknown argument: $1"; echo "Use --help"; exit 1 ;;
  esac
done

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$SDK_ROOT" ]; then
  echo "ERROR: ANDROID_SDK_ROOT or ANDROID_HOME is not set."
  echo "Please install Android SDK and set ANDROID_SDK_ROOT (eg. \$HOME/Android/Sdk)."
  exit 2
fi

echo "Using Android SDK: $SDK_ROOT"

if [ "$SKIP_BOOT" = true ]; then
  echo "--skip-boot set: will not start an emulator if none is present"
fi

ADB="$SDK_ROOT/platform-tools/adb"
EMULATOR="$SDK_ROOT/emulator/emulator"
AVDMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

if [ ! -x "$ADB" ]; then
  echo "ERROR: adb not found at $ADB"
  exit 2
fi
# Ensure adb server is running and in a clean state for reliable emulator connectivity
echo "Starting adb server (if not running)"
"$ADB" start-server >/dev/null 2>&1 || true

if [ ! -x "$EMULATOR" ]; then
  echo "ERROR: emulator not found at $EMULATOR"
  exit 2
fi

AVD_NAME="${TEST_AVD_NAME:-test_avd}"
# Allow overriding the system image via environment to support non-KVM setups (e.g. arm images)
IMAGE_PATH="${IMAGE_PATH:-system-images;android-31;google_apis;x86_64}"

echo "Checking for AVD $AVD_NAME"
if ! "$SDK_ROOT/emulator/emulator" -list-avds | grep -q "^$AVD_NAME$"; then
  echo "AVD $AVD_NAME not found. Creating..."
  if [ ! -x "$SDKMANAGER" ] || [ ! -x "$AVDMANAGER" ]; then
    echo "sdkmanager/avdmanager not found under cmdline-tools."
    echo "Install cmdline-tools and required system images, e.g."
    echo "  sdkmanager \"platform-tools\" \"emulator\" \"platforms;android-31\" \"${IMAGE_PATH}\""
    exit 3
  fi

  echo "Installing minimal SDK packages (may require network)"
  yes | "$SDKMANAGER" --sdk_root="$SDK_ROOT" "platform-tools" "emulator" "platforms;android-31" "$IMAGE_PATH" || true

  echo "Creating AVD (no interactive)."
  echo "no" | "$AVDMANAGER" create avd -n "$AVD_NAME" -k "$IMAGE_PATH" -f || true
fi

# Boot emulator if not running
if ! "$ADB" devices | sed 1d | awk '{print $2}' | grep -q device; then
  echo "No device/emulator detected. Starting emulator $AVD_NAME"
  if [ "$SKIP_BOOT" = true ]; then
    echo "No emulator present and --skip-boot was set. Exiting."; exit 4
  fi
  # Use flags to avoid snapshot restores and GUI dependencies for repeatable non-interactive runs
  EMULATOR_ARGS=( -avd "$AVD_NAME" -no-window -gpu swiftshader_indirect -no-audio -no-boot-anim -no-snapshot -no-snapshot-load -no-snapshot-save )
  if [ "$FRESH_EMULATOR" = true ]; then
    # wipe data to ensure a clean, repeatable emulator state
    EMULATOR_ARGS+=( -wipe-data )
  fi
  nohup "$EMULATOR" "${EMULATOR_ARGS[@]}" > "$ARTIFACTS_DIR/emulator.log" 2>&1 &
  EMU_PID=$!
  echo "Emulator PID: $EMU_PID"
  echo "Waiting for emulator to appear in adb..."
  # Give emulator more time to register with adb on slower systems
  ADB_APPEAR_TIMEOUT=${ADB_APPEAR_TIMEOUT:-300}
  timeout=$ADB_APPEAR_TIMEOUT
  while [ $timeout -gt 0 ]; do
    if "$ADB" devices | sed 1d | awk '{print $2}' | grep -q device; then
      break
    fi
    sleep 1
    timeout=$((timeout-1))
  done
  if [ $timeout -le 0 ]; then
    echo "ERROR: emulator failed to appear in adb within timeout ($ADB_APPEAR_TIMEOUT s). See $ARTIFACTS_DIR/emulator.log"
    echo "adb server status:"
    "$ADB" devices -l > "$ARTIFACTS_DIR/adb_devices_after_launch.txt" 2>&1 || true
    exit 4
  fi
fi

echo "Waiting for boot completion..."
# Allow longer boot timeout for CI or underpowered hosts
BOOT_TIMEOUT=${BOOT_TIMEOUT:-600}
while [ $BOOT_TIMEOUT -gt 0 ]; do
  BOOT_COMPLETED=$($ADB shell getprop sys.boot_completed 2>/dev/null || echo 0)
  if [ "$BOOT_COMPLETED" = "1" ]; then
    break
  fi
  sleep 1
  BOOT_TIMEOUT=$((BOOT_TIMEOUT-1))
done
if [ $BOOT_TIMEOUT -le 0 ]; then
  echo "ERROR: emulator did not finish booting in time"
  exit 5
fi

echo "Emulator is ready"

# Build APK
if [ "$SKIP_BUILD" = true ] && [ -n "$APK_OVERRIDE" ]; then
  APK_PATH="$APK_OVERRIDE"
  echo "--skip-build: using APK from --apk: $APK_PATH"
elif [ "$SKIP_BUILD" = true ]; then
  echo "--skip-build set but no --apk provided. Exiting."; exit 6
else
  BUILD_SCRIPT="$SCRIPT_DIR/build_android_debug.sh"
  if [ ! -x "$BUILD_SCRIPT" ]; then
    echo "ERROR: build script not found or not executable at $BUILD_SCRIPT"
    echo "Make sure scripts/build_android_debug.sh exists and is runnable."
    exit 6
  fi

  echo "Building APK..."
  APK_PATH=$("$BUILD_SCRIPT") || { echo "Build script failed"; exit 7; }
  echo "APK produced at: $APK_PATH"
  if [ ! -f "$APK_PATH" ]; then
    echo "ERROR: APK not found at path reported by build script"
    exit 8
  fi
fi

echo "Installing APK on emulator..."
# Ensure a prior install won't block us due to mismatched signatures. Be conservative: uninstall if present.
PACKAGE_NAME="center.dx.wingout"
echo "Checking for existing package $PACKAGE_NAME on device"
if $ADB shell pm list packages | grep -q "^package:$PACKAGE_NAME$"; then
  echo "Existing installation detected. Uninstalling to ensure a clean install..."
  $ADB uninstall "$PACKAGE_NAME" > "$ARTIFACTS_DIR/adb_uninstall.txt" 2>&1 || true
fi

# Install and capture output
$ADB install -r "$APK_PATH" > "$ARTIFACTS_DIR/adb_install.txt" 2>&1 || { echo "adb install failed; see $ARTIFACTS_DIR/adb_install.txt"; exit 9; }

echo "Running Wingout smoke test"
SMOKE_SCRIPT_CAND1="$SCRIPT_DIR/smoke_run_wingout.sh"
SMOKE_SCRIPT_CAND2="$REPO_ROOT/tools/smoke_run_wingout.sh"
if [ -x "$SMOKE_SCRIPT_CAND1" ]; then
  SMOKE_SCRIPT="$SMOKE_SCRIPT_CAND1"
elif [ -x "$SMOKE_SCRIPT_CAND2" ]; then
  SMOKE_SCRIPT="$SMOKE_SCRIPT_CAND2"
else
  echo "ERROR: smoke script not found or not executable. Looked in: $SMOKE_SCRIPT_CAND1 and $SMOKE_SCRIPT_CAND2"
  exit 10
fi

"$SMOKE_SCRIPT" "$APK_PATH" "$ARTIFACTS_DIR" || { echo "Smoke test failed"; exit 11; }

echo "Running ffstream emulator connectivity tests (go tests)"
if [ -d "$REPO_ROOT/import/ffstream/e2e" ]; then
  (cd "$REPO_ROOT/import/ffstream/e2e" && go test -v . -run TestEmulatorConnectivity -timeout 120s) || echo "ffstream tests failed"
else
  echo "ffstream e2e tests not found; skipped"
fi

echo "All steps finished. Artifacts in $ARTIFACTS_DIR"
exit 0
