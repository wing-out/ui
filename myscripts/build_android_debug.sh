#!/bin/bash

# This script builds a Debug APK for the wingout project,
# mimicking the behavior of QtCreator.

set -e

# Ensure a UTF-8 locale is used
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Project and Build configuration
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
BUILD_DIR="$PROJECT_ROOT/build-android-debug"
# Allow overriding Qt paths and versions via environment for flexibility in different machines
QT_VERSION="${QT_VERSION:-6.10.1}"
QT_BASE_DIR="${QT_BASE_DIR:-/home/streaming/Qt/$QT_VERSION}"
QT_ANDROID_DIR="${QT_ANDROID_DIR:-$QT_BASE_DIR/android_arm64_v8a}"
QT_HOST_DIR="${QT_HOST_DIR:-$QT_BASE_DIR/gcc_64}"
QT_CMAKE="${QT_CMAKE:-$QT_ANDROID_DIR/bin/qt-cmake}"

# Android Environment (allow overrides from environment)
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/home/streaming/Android/Sdk}"
ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$ANDROID_SDK_ROOT/ndk/27.2.12479018}"
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export ANDROID_SDK_ROOT ANDROID_NDK_ROOT JAVA_HOME

# Use ccache for all CMake builds (including sub-builds for different ABIs)
export CMAKE_C_COMPILER_LAUNCHER=ccache
export CMAKE_CXX_COMPILER_LAUNCHER=ccache
export NDK_CCACHE=ccache
export ANDROID_CCACHE=ccache

# Verify essential tools
if [ ! -f "$QT_CMAKE" ]; then
    echo "Error: qt-cmake not found at $QT_CMAKE"
    exit 1
fi

if [ ! -d "$ANDROID_NDK_ROOT" ]; then
    echo "Error: Android NDK not found at $ANDROID_NDK_ROOT"
    exit 1
fi

if ! command -v ccache &> /dev/null; then
    echo "Error: ccache not found. Please install it."
    exit 1
fi

# Initialize submodules if not already done
echo "--> Initializing git submodules..."
cd "$PROJECT_ROOT"
git submodule update --init --recursive || true

# dxProducer address is handled at runtime by the application.
# Remove build-time probing/patching of Main.qml. The application reads
# and saves dxProducer address from the platform config dir at runtime.

echo "--> Ensuring build directory exists: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

# If an existing CMake cache or CMakeFiles from a different generator exists,
# remove it to avoid generator mismatch errors (see CMake message in CI/local runs).
if [ -f "$BUILD_DIR/CMakeCache.txt" ] || [ -d "$BUILD_DIR/CMakeFiles" ]; then
    echo "--> Cleaning stale CMake cache in $BUILD_DIR to avoid generator mismatch"
    rm -rf "$BUILD_DIR/CMakeCache.txt" "$BUILD_DIR/CMakeFiles" || true
fi

ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"
mkdir -p "$ARTIFACTS_DIR"
CONFIG_LOG="$ARTIFACTS_DIR/cmake_config.log"
BUILD_LOG="$ARTIFACTS_DIR/cmake_build.log"

echo "--> Configuring CMake for Android (Debug)..."
# Always run configuration so we force usage of the Android Qt toolchain and
# avoid accidental use of system Qt packages.
set +e
"$QT_CMAKE" \
    -S "$PROJECT_ROOT" \
    -B "$BUILD_DIR" \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_PREFIX_PATH="$QT_ANDROID_DIR" \
    -DCMAKE_IGNORE_PATH="/usr/lib/x86_64-linux-gnu/cmake" \
    -DQt6_DIR="$QT_ANDROID_DIR/lib/cmake/Qt6" \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DQT_HOST_PATH="$QT_HOST_DIR" \
    -DANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" \
    -DANDROID_NDK_ROOT="$ANDROID_NDK_ROOT" \
    -DANDROID_ABI="arm64-v8a" \
    -DANDROID_CCACHE=ccache \
    -DQT_ANDROID_BUILD_ALL_ABIS=OFF \
    -DQT_ANDROID_MULTI_ABI_FORWARD_VARS="CMAKE_C_COMPILER_LAUNCHER;CMAKE_CXX_COMPILER_LAUNCHER;ANDROID_CCACHE;NDK_CCACHE" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON 2>&1 | tee "$CONFIG_LOG"
cmake_exit=${PIPESTATUS[0]}
set -e
if [ $cmake_exit -ne 0 ]; then
    echo "Error: CMake configuration failed. See $CONFIG_LOG" >&2
    # Helpful diagnostics for missing Qt modules
    if [ -d "$QT_ANDROID_DIR/lib/cmake/Qt6" ]; then
        echo "Listing Qt6 CMake packages available in $QT_ANDROID_DIR/lib/cmake/Qt6:" >> "$CONFIG_LOG" 2>&1
        ls -la "$QT_ANDROID_DIR/lib/cmake/Qt6" >> "$CONFIG_LOG" 2>&1 || true
    else
        echo "Qt6 CMake directory not found at $QT_ANDROID_DIR/lib/cmake/Qt6" >> "$CONFIG_LOG" 2>&1
    fi
    # If error mentions Qt6::Bluetooth, add a hint
    if grep -q "Qt6::Bluetooth" "$CONFIG_LOG" 2>/dev/null; then
        echo "\nDiagnostic: CMake failed because Qt Bluetooth module was not found for the Android Qt installation." | tee -a "$CONFIG_LOG" >&2
        echo "If you need Bluetooth support, ensure the Qt Android kit at $QT_ANDROID_DIR includes the Bluetooth module." | tee -a "$CONFIG_LOG" >&2
    fi
    exit 1
fi

# Build the project
echo "--> Building project..."
ccache -z
set +e
cmake --build "$BUILD_DIR" --parallel 8 --target apk 2>&1 | tee "$BUILD_LOG"
build_exit=${PIPESTATUS[0]}
set -e
ccache -s
if [ $build_exit -ne 0 ]; then
    echo "Error: Build failed. See $BUILD_LOG" >&2
    exit 1
fi

# Locate the generated APK
echo "--> Locating generated APK..."
APK_PATH=$(find "$BUILD_DIR" -name "*-debug.apk" | head -n 1)

if [ -n "$APK_PATH" ]; then
    # Write machine-readable result and print APK path on the last stdout line
    mkdir -p "$BUILD_DIR"
    echo "$APK_PATH" > "$BUILD_DIR/last_apk.txt"
    echo "Success! APK found at: $APK_PATH" >&2
    # Print path as the last stdout line for automation consumers
    echo "$APK_PATH"
else
    echo "Warning: Build finished but APK could not be located in $BUILD_DIR"
    exit 1
fi

echo "Build completed successfully."
