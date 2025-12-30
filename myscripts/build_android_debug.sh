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
QT_VERSION="6.10.1"
QT_BASE_DIR="/workspaces/xaionaro-go/Qt/$QT_VERSION"
QT_ANDROID_DIR="$QT_BASE_DIR/android_arm64_v8a"
QT_HOST_DIR="$QT_BASE_DIR/gcc_64"
QT_CMAKE="$QT_ANDROID_DIR/bin/qt-cmake"

# Android Environment
export ANDROID_SDK_ROOT="/opt/android-sdk"
export ANDROID_NDK_ROOT="$ANDROID_SDK_ROOT/ndk/26.1.10909125"
export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"

# Verify essential tools
if [ ! -f "$QT_CMAKE" ]; then
    echo "Error: qt-cmake not found at $QT_CMAKE"
    exit 1
fi

if [ ! -d "$ANDROID_NDK_ROOT" ]; then
    echo "Error: Android NDK not found at $ANDROID_NDK_ROOT"
    exit 1
fi

# Initialize submodules if not already done
echo "--> Initializing git submodules..."
cd "$PROJECT_ROOT"
git submodule update --init --recursive

# Prepare build directory
if [ -d "$BUILD_DIR" ]; then
    echo "--> Cleaning existing build directory: $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi
echo "--> Creating build directory: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Configure the project
# We use Ninja as it is the default for QtCreator
echo "--> Configuring CMake for Android (Debug)..."
"$QT_CMAKE" \
    -S "$PROJECT_ROOT" \
    -B "$BUILD_DIR" \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DQT_HOST_PATH="$QT_HOST_DIR" \
    -DANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" \
    -DANDROID_NDK_ROOT="$ANDROID_NDK_ROOT" \
    -DANDROID_ABI="arm64-v8a" \
    -DQT_ANDROID_BUILD_ALL_ABIS=OFF \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

# Build the project
echo "--> Building project..."
cmake --build "$BUILD_DIR" --parallel $(nproc)

# Create the APK
# In Qt 6, the 'install' target triggers androiddeployqt to create the APK
echo "--> Creating APK (running install target)..."
cmake --build "$BUILD_DIR" --target install

# Locate the generated APK
echo "--> Locating generated APK..."
APK_PATH=$(find "$BUILD_DIR" -name "*-debug.apk" | head -n 1)

if [ -n "$APK_PATH" ]; then
    echo "Success! APK found at: $APK_PATH"
else
    echo "Warning: Build finished but APK could not be located in $BUILD_DIR"
    exit 1
fi

echo "Build completed successfully."
