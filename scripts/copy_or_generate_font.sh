#!/bin/bash

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

FONT_PATH=$1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_ROOT/build-android/WingOut/fonts/FreeSans.ttf" ]; then
    cp "$PROJECT_ROOT/build-android/WingOut/fonts/FreeSans.ttf" "$FONT_PATH"
elif [ -f "$PROJECT_ROOT/build-android-debug/WingOut/fonts/FreeSans.ttf" ]; then
    cp "$PROJECT_ROOT/build-android-debug/WingOut/fonts/FreeSans.ttf" "$FONT_PATH"
else
    make -C "$PROJECT_ROOT/import/gnu-freefont/sfd" FreeSans.ttf && mv "$PROJECT_ROOT/import/gnu-freefont/sfd/FreeSans.ttf" "$FONT_PATH"
fi
