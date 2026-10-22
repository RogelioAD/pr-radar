#!/usr/bin/env python3
"""A PNG reader, in the standard library.

`mascot.py` already writes one by hand because the repo has no image
dependency and is not getting one for a preview. Reading is the same bargain
in the other direction: importing a reference drawing is a one-off, and a
one-off is not worth a dependency everyone who builds the project then has
to install.

Handles what actually turns up: 8-bit greyscale, RGB, palette and RGBA, with
every filter type. No interlacing — Adam7 is a different unfilter loop and
nothing anybody exports uses it by default.
"""
import struct
import zlib


def read(path):
    """-> (width, height, pixels) where pixels[y][x] is (r, g, b, a)."""
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', "not a PNG"

    chunks = {}
    idat = b''
    pos = 8
    while pos < len(data):
        length, tag = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if tag == b'IDAT':
            idat += body
        else:
            chunks[tag] = body
        pos += 12 + length

    width, height, depth, colour, _, _, interlace = struct.unpack(
        '>IIBBBBB', chunks[b'IHDR'])
    assert depth == 8, f"only 8-bit samples supported, got {depth}"
    assert interlace == 0, "interlaced PNGs are not supported"

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    palette = chunks.get(b'PLTE', b'')
    alpha = chunks.get(b'tRNS', b'')

    raw = zlib.decompress(idat)
    stride = width * channels
    out = []
    previous = bytearray(stride)
    pos = 0
    for _ in range(height):
        filt = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = previous[i]
            c = previous[i - channels] if i >= channels else 0
            if filt == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filt == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        previous = line

        row = []
        for x in range(width):
            px = line[x * channels:(x + 1) * channels]
            if colour == 0:
                row.append((px[0], px[0], px[0], 255))
            elif colour == 2:
                row.append((px[0], px[1], px[2], 255))
            elif colour == 3:
                i = px[0]
                a = alpha[i] if i < len(alpha) else 255
                row.append((palette[i * 3], palette[i * 3 + 1],
                            palette[i * 3 + 2], a))
            elif colour == 4:
                row.append((px[0], px[0], px[0], px[1]))
            else:
                row.append((px[0], px[1], px[2], px[3]))
        out.append(row)
    return width, height, out
