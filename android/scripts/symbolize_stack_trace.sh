#!/bin/bash

SYMBOLIZER='/home/streaming/Android/Sdk/ndk/27.2.12479018/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-addr2line'
SYMBOLS_DIR="./build/Android_Qt_6_9_1_Clang_arm64_v8a-Debug/android-build-wingout/libs/arm64-v8a"

while IFS= read -r line; do
    # Extract .so file and OFFSET if present in the line
    if [[ "$line" =~ ([^/]+\.so)\+0x([0-9a-fA-F]+) ]]; then
        LIBFILE="${BASH_REMATCH[1]}"
        OFFSET="${BASH_REMATCH[2]}"
        LIBFILE_PATH="$SYMBOLS_DIR/$LIBFILE"
        if [ -f "$LIBFILE_PATH" ]; then
            echo "----- $LIBFILE (0x$OFFSET) -----"
            $SYMBOLIZER -f -e "$LIBFILE_PATH" "0x$OFFSET"
        else
            echo "WARNING: $LIBFILE_PATH not found"
        fi
    fi
done
