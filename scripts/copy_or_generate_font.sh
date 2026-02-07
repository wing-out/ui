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
    TWEAKS_DIR="$PROJECT_ROOT/import/gnu-freefont/tools/generate/tweeks"
    
    # Backup original scripts
    cp "$TWEAKS_DIR/correct_fsSelection.py" "$TWEAKS_DIR/correct_fsSelection.py.bak"
    cp "$TWEAKS_DIR/OpenType/table.py" "$TWEAKS_DIR/OpenType/table.py.bak"
    cp "$TWEAKS_DIR/OpenType/checksum.py" "$TWEAKS_DIR/OpenType/checksum.py.bak"
    
    # Copy patched scripts from tools/font-generator/
    cp "$PROJECT_ROOT/tools/font-generator/correct_fsSelection.py" "$TWEAKS_DIR/"
    cp "$PROJECT_ROOT/tools/font-generator/OpenType/table.py" "$TWEAKS_DIR/OpenType/"
    cp "$PROJECT_ROOT/tools/font-generator/OpenType/checksum.py" "$TWEAKS_DIR/OpenType/"
    
    # Run make
    make -C "$PROJECT_ROOT/import/gnu-freefont/sfd" FreeSans.ttf
    
    # Move the result
    mv "$PROJECT_ROOT/import/gnu-freefont/sfd/FreeSans.ttf" "$FONT_PATH"
    
    # Restore original scripts
    mv "$TWEAKS_DIR/correct_fsSelection.py.bak" "$TWEAKS_DIR/correct_fsSelection.py"
    mv "$TWEAKS_DIR/OpenType/table.py.bak" "$TWEAKS_DIR/OpenType/table.py"
    mv "$TWEAKS_DIR/OpenType/checksum.py.bak" "$TWEAKS_DIR/OpenType/checksum.py"
fi
