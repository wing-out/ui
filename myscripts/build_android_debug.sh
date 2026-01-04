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
git submodule update --init --recursive

if ! [ -d "$BUILD_DIR" ]; then
    echo "--> Creating build directory: $BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    echo "--> Configuring CMake for Android (Debug)..."
    "$QT_CMAKE" \
        -S "$PROJECT_ROOT" \
        -B "$BUILD_DIR" \
        -GNinja \
        -DCMAKE_BUILD_TYPE=Debug \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DQT_HOST_PATH="$QT_HOST_DIR" \
        -DANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" \
        -DANDROID_NDK_ROOT="$ANDROID_NDK_ROOT" \
        -DANDROID_ABI="arm64-v8a" \
        -DANDROID_CCACHE=ccache \
        -DQT_ANDROID_BUILD_ALL_ABIS=OFF \
        -DQT_ANDROID_MULTI_ABI_FORWARD_VARS="CMAKE_C_COMPILER_LAUNCHER;CMAKE_CXX_COMPILER_LAUNCHER;ANDROID_CCACHE;NDK_CCACHE" \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
fi

# Build the project
echo "--> Building project..."
ccache -z
cmake --build "$BUILD_DIR" --parallel 8 --target install
ccache -s

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
