#!/bin/bash

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

FONT_PATH=$1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TWEAKS_DIR="$PROJECT_ROOT/import/gnu-freefont/tools/generate/tweeks"
SFD_DIR="$PROJECT_ROOT/import/gnu-freefont/sfd"

# Backup original scripts and Makefile
cp "$TWEAKS_DIR/correct_fsSelection.py" "$TWEAKS_DIR/correct_fsSelection.py.bak"
cp "$TWEAKS_DIR/set_isFixedPitch.py" "$TWEAKS_DIR/set_isFixedPitch.py.bak"
cp "$TWEAKS_DIR/OpenType/table.py" "$TWEAKS_DIR/OpenType/table.py.bak"
cp "$TWEAKS_DIR/OpenType/checksum.py" "$TWEAKS_DIR/OpenType/checksum.py.bak"
cp "$SFD_DIR/Makefile" "$SFD_DIR/Makefile.bak"

# Copy patched scripts from tools/font-generator/
cp "$PROJECT_ROOT/tools/font-generator/correct_fsSelection.py" "$TWEAKS_DIR/"
cp "$PROJECT_ROOT/tools/font-generator/set_isFixedPitch.py" "$TWEAKS_DIR/"
cp "$PROJECT_ROOT/tools/font-generator/OpenType/table.py" "$TWEAKS_DIR/OpenType/"
cp "$PROJECT_ROOT/tools/font-generator/OpenType/checksum.py" "$TWEAKS_DIR/OpenType/"

# Patch Makefile to use python3 for tweaks and avoid shell-execution issues
sed -i 's|$(IFP) $@|python3 $(IFP) $@|' "$SFD_DIR/Makefile"
sed -i 's|$(CFS) $@|python3 $(CFS) $@|' "$SFD_DIR/Makefile"

# Run make
make -C "$SFD_DIR" FreeSans.ttf

# Move the result
mv "$SFD_DIR/FreeSans.ttf" "$FONT_PATH"

# Restore original files
mv "$TWEAKS_DIR/correct_fsSelection.py.bak" "$TWEAKS_DIR/correct_fsSelection.py"
mv "$TWEAKS_DIR/set_isFixedPitch.py.bak" "$TWEAKS_DIR/set_isFixedPitch.py"
mv "$TWEAKS_DIR/OpenType/table.py.bak" "$TWEAKS_DIR/OpenType/table.py"
mv "$TWEAKS_DIR/OpenType/checksum.py.bak" "$TWEAKS_DIR/OpenType/checksum.py"
mv "$SFD_DIR/Makefile.bak" "$SFD_DIR/Makefile"
