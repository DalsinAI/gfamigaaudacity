#!/usr/bin/env python3
# Writes Audacity's Workbench tool icon (a classic DiskObject, 4 colours):
# a double-click runs the program with the stack it needs.
#   python3 make-icon.py OUT/Audacity.info
# Copyright (c) 2026 AmiCradle Team
import struct
import sys

W, H, DEPTH = 48, 26, 2
STACK = 1048576

# 0 grey, 1 black, 2 white, 3 blue (the Workbench pens)
def picture():
    px = [[0] * W for _ in range(H)]
    for x in range(2, W - 2):          # frame
        px[1][x] = 2
        px[H - 2][x] = 1
    for y in range(1, H - 1):
        px[y][2] = 2
        px[y][W - 3] = 1
    mid = H // 2
    for x in range(4, W - 4):          # the centre line
        px[mid][x] = 1
    # a waveform: bars of falling and rising height
    heights = [2, 5, 8, 10, 7, 4, 9, 6, 3, 8, 10, 5, 2, 6, 9, 4, 7, 3, 1]
    for i, h in enumerate(heights):
        x = 6 + i * 2
        for y in range(mid - h, mid + h + 1):
            if 2 < y < H - 2:
                px[y][x] = 3
    return px

def planes(px):
    row_words = (W + 15) // 16
    out = b""
    for plane in range(DEPTH):
        for y in range(H):
            bits = 0
            for x in range(row_words * 16):
                bit = (px[y][x] >> plane) & 1 if x < W else 0
                bits = (bits << 1) | bit
            out += bits.to_bytes(row_words * 2, "big")
    return out

def main():
    data = planes(picture())
    gadget = struct.pack(">IhhHHHHHIIIIIHI",
                         0, 0, 0, W, H + 1,
                         0x0004,          # GFLG_GADGIMAGE, complement when selected
                         0x0003,          # RELVERIFY | GADGIMMEDIATE
                         0x0001,          # BOOLGADGET
                         1, 0, 0, 0, 0, 0,
                         1)               # UserData 1: a 2.x icon
    disk = struct.pack(">HH", 0xE310, 1) + gadget + struct.pack(">BBIIiiIII",
                         3, 0,            # WBTOOL
                         0, 0,            # no default tool, no tool types
                         -0x80000000, -0x80000000,   # NO_ICON_POSITION
                         0, 0, STACK)
    assert len(disk) == 78, len(disk)
    image = struct.pack(">hhHHHIBBI", 0, 0, W, H, DEPTH, 1, 3, 0, 0)
    with open(sys.argv[1], "wb") as f:
        f.write(disk + image + data)

if __name__ == "__main__":
    main()
