#!/usr/bin/env python3
# theme-compiler.py - build-host replacement for Audacity's image-compiler.
#
# Audacity's image-compiler is a wx program that runs at build time.  In a
# cross build it would be an Amiga binary, so this script does the same job
# on the build host: it packs each theme's Components/*.png and Colors.txt
# into one 440x836 RGBA image, exactly as ThemeBase::CreateOneImageCache
# lays it out, and writes the PNG bytes as a C initialiser list
# (<Theme>ThemeAsCeeCode.h) for lib-theme-resources.
#
# Usage: theme-compiler.py <lib-theme-resources dir> <AllThemeResources.h>
#        theme [theme...]
#
# Copyright (c) 2026 AmiCradle Team

import re
import struct
import sys
import zlib

CACHE_W, CACHE_H = 440, 836
COL_SIZE = 10
F_PAIRED, F_CURSOR, F_NEWLINE, F_INTERNAL, F_SKIP = 1, 2, 4, 8, 16
FLAG_NAMES = {"resFlagNone": 0, "resFlagPaired": F_PAIRED,
              "resFlagCursor": F_CURSOR, "resFlagNewLine": F_NEWLINE,
              "resFlagInternal": F_INTERNAL, "resFlagSkip": F_SKIP}
HEADER_NAMES = {"light": "LightThemeAsCeeCode",
                "dark": "DarkThemeAsCeeCode",
                "classic": "ClassicThemeAsCeeCode",
                "high-contrast": "HighContrastThemeAsCeeCode"}


def die(msg):
    sys.stderr.write("theme-compiler: %s\n" % msg)
    sys.exit(1)


# ---------------------------------------------------------------- resources

def read_resources(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    images, colours = [], []
    flags = F_PAIRED
    tok = re.compile(
        r"SET_THEME_FLAGS\(\s*([^)]*?)\s*\)"
        r"|DEFINE_IMAGE\(\s*(\w+)\s*,\s*wxImage\(\s*(\d+)\s*,\s*(\d+)\s*\)"
        r"\s*,\s*wxT\(\s*\"([^\"]*)\"\s*\)\s*\)"
        r"|DEFINE_COLOUR\(\s*(\w+)\s*,\s*wxColour\(([^)]*)\)"
        r"\s*,\s*wxT\(\s*\"([^\"]*)\"\s*\)\s*\)")
    for m in tok.finditer(text):
        if m.group(1) is not None:
            flags = 0
            for part in m.group(1).split("|"):
                part = part.strip()
                if part not in FLAG_NAMES:
                    die("unknown flag %r" % part)
                flags |= FLAG_NAMES[part]
        elif m.group(2) is not None:
            # RegisterImage clears resFlagSkip in the caller's flags
            flags &= ~F_SKIP
            images.append((m.group(5), int(m.group(3)), int(m.group(4)),
                           flags))
        else:
            rgb = [int(v.strip(), 0) for v in m.group(7).split(",")][:3]
            colours.append((m.group(8), tuple(rgb)))
    if text.count("DEFINE_IMAGE(") != len(images):
        die("parsed %d of %d DEFINE_IMAGE" %
            (len(images), text.count("DEFINE_IMAGE(")))
    if text.count("DEFINE_COLOUR(") != len(colours):
        die("parsed %d of %d DEFINE_COLOUR" %
            (len(colours), text.count("DEFINE_COLOUR(")))
    return images, colours


# ---------------------------------------------------------------- PNG in

def png_read(path):
    """Return (w, h, rgba bytearray) for a non-interlaced PNG."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        die("%s: not a PNG" % path)
    pos, idat, plte, trns = 8, b"", None, None
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, depth, ctype, _c, _f, inter = struct.unpack(">IIBBBBB", body)
        elif typ == b"PLTE":
            plte = body
        elif typ == b"tRNS":
            trns = body
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
    if inter:
        die("%s: interlaced PNG not supported" % path)
    chans = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    bpp_bits = chans * depth
    stride = (w * bpp_bits + 7) // 8
    bpp = max(1, bpp_bits // 8)
    raw = zlib.decompress(idat)
    rows, prev, p = [], bytearray(stride), 0
    for _y in range(h):
        ft = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ft == 1:
                line[i] = (line[i] + a) & 255
            elif ft == 2:
                line[i] = (line[i] + b) & 255
            elif ft == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif ft == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
            elif ft != 0:
                die("%s: bad filter %d" % (path, ft))
        rows.append(line)
        prev = line

    def samples(line):
        if depth == 8:
            return list(line)
        if depth == 16:
            return [line[i] for i in range(0, len(line), 2)]
        out, mask = [], (1 << depth) - 1
        for byte in line:
            for shift in range(8 - depth, -1, -depth):
                out.append((byte >> shift) & mask)
        return out

    out = bytearray(w * h * 4)
    scale = 255 // ((1 << depth) - 1) if depth < 8 else 1
    key = None
    if trns is not None and ctype == 0:
        key = struct.unpack(">H", trns[:2])[0]
    elif trns is not None and ctype == 2:
        key = struct.unpack(">HHH", trns[:6])
    for y, line in enumerate(rows):
        s = samples(line)
        for x in range(w):
            o = (y * w + x) * 4
            if ctype == 3:
                i = s[x]
                r, g, b = plte[3 * i:3 * i + 3]
                a = trns[i] if (trns is not None and i < len(trns)) else 255
            elif ctype == 0:
                v = s[x]
                a = 0 if key is not None and v == key else 255
                r = g = b = v * scale
            elif ctype == 4:
                r = g = b = s[2 * x]
                a = s[2 * x + 1]
            elif ctype == 2:
                r, g, b = s[3 * x:3 * x + 3]
                a = 0 if key is not None and (r, g, b) == key else 255
            else:
                r, g, b, a = s[4 * x:4 * x + 4]
            out[o:o + 4] = bytes((r, g, b, a))
    return w, h, out


# ---------------------------------------------------------------- PNG out

def png_write(w, h, rgba):
    def chunk(typ, body):
        return (struct.pack(">I", len(body)) + typ + body +
                struct.pack(">I", zlib.crc32(typ + body) & 0xffffffff))
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += rgba[y * w * 4:(y + 1) * w * 4]
    return (b"\x89PNG\r\n\x1a\n" +
            chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(bytes(raw), 9)) +
            chunk(b"IEND", b""))


# ---------------------------------------------------------------- packer
# A line-by-line copy of FlowPacker in lib-theme/Theme.cpp.

class FlowPacker:
    def __init__(self, width):
        self.mFlags = F_PAIRED
        self.mxPos = self.myPos = self.myHeight = 0
        self.mBorderWidth = 1
        self.iImageGroupSize, self.iImageGroupIndex = 1, -1
        self.mOldFlags, self.myPosBase = F_PAIRED, 0
        self.mxCacheWidth = width
        self.mComponentWidth = self.mComponentHeight = 0
        self.SetNewGroup(1)

    def SetNewGroup(self, size):
        self.myPosBase += self.myHeight * self.iImageGroupSize
        self.mxPos = 0
        self.mOldFlags = self.mFlags
        self.iImageGroupSize = size
        self.iImageGroupIndex = -1
        self.mComponentWidth = 0

    def SetColourGroup(self):
        self.myPosBase = 750
        self.mxPos = 0
        self.mOldFlags = self.mFlags
        self.iImageGroupSize = 1
        self.iImageGroupIndex = -1
        self.mComponentWidth = 0
        self.myHeight = 11

    def GetNextPosition(self, xs, ys):
        xs += 2 * self.mBorderWidth
        ys += 2 * self.mBorderWidth
        if ys > self.myHeight or ((self.mFlags ^ self.mOldFlags) & ~F_SKIP):
            self.SetNewGroup(2 if (self.mFlags & F_PAIRED) else 1)
            self.myHeight = ys
        self.iImageGroupIndex += 1
        if self.iImageGroupIndex == self.iImageGroupSize:
            self.iImageGroupIndex = 0
            self.mxPos += self.mComponentWidth
        if self.mxPos > self.mxCacheWidth - xs:
            self.SetNewGroup(self.iImageGroupSize)
            self.iImageGroupIndex += 1
            self.myHeight = ys
        self.myPos = self.myPosBase + self.iImageGroupIndex * self.myHeight
        self.mComponentWidth = xs
        self.mComponentHeight = ys

    def Rect(self):
        return self.mxPos, self.myPos, self.mComponentWidth, \
            self.mComponentHeight

    def RectInner(self):
        b = self.mBorderWidth
        return self.mxPos + b, self.myPos + b, \
            self.mComponentWidth - 2 * b, self.mComponentHeight - 2 * b


def fill_rgb(img, rect, rgb):
    x0, y0, w, h = rect
    x1, y1 = min(x0 + w, CACHE_W), min(y0 + h, CACHE_H)
    x0, y0 = max(x0, 0), max(y0, 0)
    for y in range(y0, y1):
        for x in range(x0, x1):
            o = (y * CACHE_W + x) * 4
            img[o:o + 3] = bytes(rgb)


def paste(img, src_w, src_h, src, xoff, yoff):
    wc = min(src_w, CACHE_W - xoff)
    hc = min(src_h, CACHE_H - yoff)
    for y in range(hc):
        o = ((y + yoff) * CACHE_W + xoff) * 4
        s = y * src_w * 4
        img[o:o + wc * 4] = src[s:s + wc * 4]


def read_colours(path, names, defaults):
    values = dict(zip(names, defaults))
    expr = re.compile(r"^ *([_A-Za-z0-9]+).*#([0-9a-fA-F]{6});")
    seen = set()
    for line in open(path, encoding="utf-8", errors="replace"):
        m = expr.search(line.rstrip("\r\n"))
        if not m:
            continue
        name = m.group(1)
        if name in seen:
            sys.stderr.write("theme-compiler: duplicate colour %s\n" % name)
            continue
        seen.add(name)
        if name not in values:
            sys.stderr.write("theme-compiler: unknown colour %s\n" % name)
            continue
        v = int(m.group(2), 16)
        values[name] = ((v >> 16) & 255, (v >> 8) & 255, v & 255)
    return [values[n] for n in names]


def compile_theme(base, theme, images, colours):
    comp = "%s/%s/Components" % (base, theme)
    img = bytearray(b"\x01\x01\x01\xff" * (CACHE_W * CACHE_H))
    ctx = FlowPacker(CACHE_W)
    for name, dw, dh, flags in images:
        ctx.mFlags = flags
        if flags & F_INTERNAL:
            continue
        try:
            w, h, px = png_read("%s/%s.png" % (comp, name))
        except FileNotFoundError:
            w, h = dw, dh
            px = bytearray(b"\x00\x00\x00\xff" * (w * h))
        if (w, h) != (dw, dh):
            die("%s/%s.png is %dx%d, AllThemeResources.h says %dx%d"
                % (theme, name, w, h, dw, dh))
        ctx.GetNextPosition(w, h)
        fill_rgb(img, ctx.Rect(), (0xf2, 0xb0, 0x27))
        if not (ctx.mFlags & F_SKIP):
            paste(img, w, h, px, ctx.mxPos + ctx.mBorderWidth,
                  ctx.myPos + ctx.mBorderWidth)
        else:
            fill_rgb(img, ctx.RectInner(), (1, 1, 1))

    names = [c[0] for c in colours]
    values = read_colours("%s/Colors.txt" % comp, names,
                          [c[1] for c in colours])
    ctx.SetColourGroup()
    for rgb in values:
        ctx.GetNextPosition(COL_SIZE, COL_SIZE)
        fill_rgb(img, ctx.Rect(), (0xf2, 0xb0, 0x27))
        fill_rgb(img, ctx.RectInner(), rgb)
        for y in range(COL_SIZE):
            for x in range(COL_SIZE):
                img[((ctx.myPos + y) * CACHE_W + ctx.mxPos + x) * 4 + 3] = 255
    return png_write(CACHE_W, CACHE_H, img)


def write_header(path, png):
    name = path.rsplit("/", 1)[-1]
    out = ["///   @file %s\r\n" % name,
           "///   @brief This file was Auto-Generated.\r\n",
           "///\r\n",
           "///   It is included by Theme.cpp.\r\n",
           "///   Generated on the build host by theme-compiler.py.\r\n\r\n   "]
    for i, byte in enumerate(png, 1):
        out.append("%i," % byte)
        if i % 20 == 0:
            out.append("\r\n   ")
    out.append("\r\n")
    with open(path, "w", newline="") as f:
        f.write("".join(out))


def main():
    if len(sys.argv) < 4:
        die("usage: theme-compiler.py <resources dir> <AllThemeResources.h>"
            " theme [theme...]")
    base, res = sys.argv[1], sys.argv[2]
    images, colours = read_resources(res)
    for theme in sys.argv[3:]:
        if theme not in HEADER_NAMES:
            die("unknown theme %s" % theme)
        png = compile_theme(base, theme, images, colours)
        write_header("%s/%s.h" % (base, HEADER_NAMES[theme]), png)
        print("theme-compiler: %s: %d images, %d colours, %d bytes" %
              (theme, len(images), len(colours), len(png)))


if __name__ == "__main__":
    main()
