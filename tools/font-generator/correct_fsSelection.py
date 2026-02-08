#!/usr/bin/env python3
from __future__ import print_function
import sys
import os
from OpenType.fontdirectory import getDirectoryEntriesByTag
from OpenType.requiredtables import OS_2Table, headTable


def correct_fsSelection(filename):
    try:
        with open(filename, "rb+") as f:
            buf = bytearray(f.read())
            entries = getDirectoryEntriesByTag(buf)

            os2_entry = entries["OS/2"]
            os2 = OS_2Table(buf, os2_entry.offset)

            head_entry = entries["head"]
            head = headTable(buf, head_entry.offset)

            macStyle = head.macStyle
            fsSelection = os2.fsSelection
            if macStyle & 1:
                fsSelection |= 1 << 5
            else:
                fsSelection &= ~(1 << 5)
            if macStyle & 2:
                fsSelection |= 1 << 0
            else:
                fsSelection &= ~(1 << 0)
            if not (macStyle & 3):
                fsSelection |= 1 << 6
            else:
                fsSelection &= ~(1 << 6)
            os2.fsSelection = fsSelection

            os2.writeInto(buf, os2_entry.offset)

            # Update checksum in directory entry
            os2_entry.checkSum = os2.getChecksum()
            os2_entry.writeInto(buf, os2_entry.getOffset())

            # head table needs checksumAdjustment update too, but usually it's done at the end
            # for simplicity we just write the buf back
            f.seek(0)
            f.write(buf)
    except Exception as e:
        print("Error correcting fsSelection: " + str(e))
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: " + sys.argv[0] + " <fontfile>")
        sys.exit(1)
    correct_fsSelection(sys.argv[1])
