#!/usr/bin/env python3
"""Draw a 48-cell mascot: author half of it, get a Swift literal back.

    python3 Scripts/mascot.py --demo            # a worked example, to stdout
    python3 Scripts/mascot.py --demo --png out.png

This is the pipeline the header comment in `Mascot.swift` refers to. It made
the October four and it converted the OG cast; it is committed because the
rules it encodes were expensive to rediscover and are invisible in the output.

WHAT IT DOES, in order. The order is the whole design:

  1. You author 48 rows of 24 — the LEFT half — and it is mirrored. The
     silhouette is then symmetric to the pixel, which is a thing the test
     suite insists on and a thing you cannot reliably do by hand.

  2. The outline is taken afterwards, from 4-connectivity: a lit cell with an
     empty cell directly above, below, left or right becomes `k`. Doing it
     8-connected inks every diagonal step and the drawing turns to lace.

  3. Only then is the fill shaded, from a normal read out of the distance
     field, lit from the upper left. The interior sits on `base` and only the
     surface brightens or falls away. Dithering is confined to the band where
     two rungs genuinely meet — applied everywhere it reads as a weave rather
     than as a curve.

  4. `chassisSpec` is placed by hand, last, from a list you give it. The
     shading pass is forbidden from inventing a highlight: one it decides on
     its own turns a soft edge into a hard white rim.

TWO RULES ABOUT SHAPE that only show up once something is drawn wrong:

  * A silhouette's edge may not swing more than about three rows between
    neighbouring columns. The outline pass inks every one of those steps, and
    a bat's wings drawn steeper came out as fringe twice before this was
    understood.

  * Any spur has to be at least three columns wide. A single column reaching
    past its neighbours is outlined down both sides, which draws a spike
    rather than a fingertip.

AUTHORING ALPHABET — what you put in the half:

    .   empty            #   body, to be shaded into the six chassis rungs
    k   outline you want *inside* the silhouette (a seam, a strut)
    a   accent — the live mood colour. This is the character's tell.
    N M accent at 72% and 42%, blended toward the dark behind it. A tell
        with any depth to it is drawn in all three.
    V   visor / glass    P   cheek      f   leaf green (a stalk)
    c   bone — fixed, and not off the character's ramp. Teeth and the like:
        in `X` they come out the ramp's lightest tone, which on a red
        animal is salmon and at size is no tooth at all.
    D S B H W            a chassis rung you are placing yourself

The output alphabet is `Slot` in `Sprite.swift`. Nothing here needs to know
about colour: a character's `ChassisRamp` decides what the rungs look like.
"""

import math
import sys

W = H = 48
HALF = 24
RAMP = ['D', 'S', 'B', 'H', 'W']            # deep -> light; 'X' is by hand


# ----------------------------------------------------------------- authoring

def blank():
    """A fresh left half: 48 rows of 24 empty cells."""
    return [['.'] * HALF for _ in range(H)]



def put(half, spans, ch):
    """Paint `ch` into {row: [(from, to), ...]} spans, inclusive, clipped.

    Clips to the width of the grid it is handed, so this works on a half and
    on a whole grid without being told which it has.
    """
    wide = len(half[0]) - 1
    for y, runs in spans.items():
        for a, b in runs:
            for x in range(max(0, a), min(wide, b) + 1):
                half[y][x] = ch


def cols(spec):
    """{column: (top, bottom)} -> row spans. For anything shaped along x —
    a wing, a rib, a stalk — where thinking in columns is the natural way."""
    out = {}
    for c, (t, b) in spec.items():
        for y in range(t, b + 1):
            out.setdefault(y, []).append((c, c))
    return out


def merge(*dicts):
    out = {}
    for d in dicts:
        for y, runs in d.items():
            out.setdefault(y, []).extend(runs)
    return out


# ------------------------------------------------------------------ pipeline

def mirror(half):
    return [row + row[::-1] for row in half]


def outline(full, quiet=('a', 'N', 'M', 'f', 'P', 'V')):
    """Ink the silhouette's boundary. 4-connected — see the header."""
    lit = [[c != '.' for c in row] for row in full]

    def at(x, y):
        return 0 <= x < W and 0 <= y < H and lit[y][x]

    out = [row[:] for row in full]
    for y in range(H):
        for x in range(W):
            if not lit[y][x]:
                continue
            if at(x - 1, y) and at(x + 1, y) and at(x, y - 1) and at(x, y + 1):
                continue
            if full[y][x] == '#':
                out[y][x] = 'k'
            elif full[y][x] not in quiet:
                # Anything else on the boundary is about to be overwritten by
                # the outline, which is nearly always a mistake worth hearing
                # about — an accent cell on the edge silently stops being the
                # tell.
                print(f"  note: {full[y][x]!r} sits on the boundary at ({x},{y})",
                      file=sys.stderr)
    return out


def _reach(lit, x, y, dx, dy, cap):
    n = 0
    while n < cap:
        x += dx
        y += dy
        if not (0 <= x < W and 0 <= y < H and lit[y][x]):
            break
        n += 1
    return n


def shade(full, cap=10, throw=3.2):
    """Light from the upper left, off a normal read out of the distance field."""
    lit = [[c != '.' for c in row] for row in full]
    out = [row[:] for row in full]
    for y in range(H):
        for x in range(W):
            if full[y][x] != '#':
                continue
            dl, dr = _reach(lit, x, y, -1, 0, cap), _reach(lit, x, y, 1, 0, cap)
            dt, db = _reach(lit, x, y, 0, -1, cap), _reach(lit, x, y, 0, 1, cap)
            nx, ny = (dr - dl) / cap, (db - dt) / cap
            edge = max(0.0, 1 - min(dl, dr, dt, db) / 6.0)
            level = max(0.0, min(4.0, 3 + (0.62 * nx + 0.55 * ny) * edge * throw))
            base = int(level)
            frac = level - base
            up = frac > 0.65 or (frac > 0.35 and (x + y) % 2 == 0)
            out[y][x] = RAMP[min(4, base + (1 if up else 0))]
    return out


def specular(full, points):
    """Hand-placed highlights, last. Keep it to a handful: the test suite
    fails a sprite that is more than 5% specular, on the grounds that it is a
    rim light rather than a highlight."""
    for x, y in points:
        if full[y][x] in RAMP:
            full[y][x] = 'X'
        else:
            print(f"  note: specular at ({x},{y}) lands on {full[y][x]!r}",
                  file=sys.stderr)
    return full


def traced(name, half, down=True):
    """A half that is already *drawn* -> finished 48 rows, mirrored and
    nothing else.

    No outline and no shading pass, and that is the whole point of it: the
    tones came off a drawing somebody else lit, and running `shade` over
    them would relight a face that is already lit and flatten every plane
    it was drawn with. `outline` has nothing to do here either — there are
    no `#` cells for it to find.

    `down` steps the mirrored half one rung darker. The silhouette has to
    come back symmetric to the pixel, which the test suite insists on; the
    *colours* do not, and a face lit identically from both sides reads as
    flat. One rung is enough to say where the light is.
    """
    print(f"-- {name}", file=sys.stderr)
    darker = {'W': 'H', 'H': 'B', 'B': 'S', 'S': 'D', 'D': 'D'}
    rows = []
    for r in half:
        right = r[::-1]
        if down:
            right = ''.join(darker.get(c, c) for c in right)
        rows.append(r + right)
    assert all(len(r) == W for r in rows), "a row came out the wrong width"
    assert len(rows) == H
    return rows


def build(name, half, specs=()):
    """Half -> finished 48 rows."""
    print(f"-- {name}", file=sys.stderr)
    rows = [''.join(r) for r in specular(shade(outline(mirror(half))), specs)]
    assert all(len(r) == W for r in rows), "a row came out the wrong width"
    assert len(rows) == H
    return rows


def swift(rows, indent=12):
    """The rows as a Swift array literal, ready to paste into a `Sprite([…])`."""
    pad = ' ' * indent
    return '\n'.join(f'{pad}"{r}",' for r in rows)


# ------------------------------------------------------------------- preview

def png(path, rows, ramp, scale=7, pad=3, bg=(0.11, 0.12, 0.14),
        tint=(0.29, 0.56, 0.95)):
    """A PNG to actually look at. Written by hand because the repo has no
    image dependency and is not getting one for a preview."""
    import struct
    import zlib

    floor = (0.024, 0.035, 0.078)

    def blend(c, s):
        return tuple(c[i] * s + floor[i] * (1 - s) for i in range(3))

    fixed = {'k': (.055, .055, .055), 'a': tint, 'N': blend(tint, .72),
             'M': blend(tint, .42), 'f': (.329, .710, .420),
             'P': (.878, .561, .659), 'V': (.020, .035, .075),
             'c': (.949, .922, .843),
             'U': (.071, .125, .235), 'w': (.969, .973, .980)}
    order = 'DSBHWX'

    size = 48 + pad * 2
    w = h = size * scale
    canvas = [[tuple(int(c * 255) for c in bg)] * w for _ in range(h)]
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == '.':
                continue
            c = ramp[order.index(ch)] if ch in order else fixed.get(ch)
            if c is None:
                print(f"  note: no preview colour for {ch!r}", file=sys.stderr)
                continue
            rgb = tuple(int(v * 255) for v in c)
            for dy in range(scale):
                for dx in range(scale):
                    canvas[(y + pad) * scale + dy][(x + pad) * scale + dx] = rgb

    raw = b''.join(b'\x00' + bytes(v for px in r for v in px) for r in canvas)

    def chunk(tag, data):
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))

    open(path, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9))
        + chunk(b'IEND', b''))
    print(f"wrote {path}", file=sys.stderr)


# ---------------------------------------------------------------------- demo

def demo():
    """A worked example: a squat robot. Read this rather than the docstring
    if you are about to draw one."""
    g = blank()
    # The body, as a left edge per row — everything from there to the centre
    # is filled, and mirroring does the rest.
    lefts = {6: 17, 7: 14, 8: 12, 9: 11, 10: 10, 11: 9, 12: 9, 13: 8, 14: 8,
             15: 8, 16: 8, 17: 8, 18: 8, 19: 8, 20: 9, 21: 9, 22: 10, 23: 11}
    put(g, {y: [(l, 23)] for y, l in lefts.items()}, '#')
    put(g, {y: [(11, 23)] for y in range(24, 38)}, '#')
    put(g, {38: [(12, 23)], 39: [(13, 23)], 40: [(14, 23)]}, '#')
    put(g, cols({15: (41, 46), 16: (41, 46), 17: (41, 46), 18: (41, 46)}), '#')
    put(g, {y: [(21, 23)] for y in range(0, 6)}, '#')      # antenna
    put(g, {0: [(22, 23)], 1: [(22, 23)]}, 'a')            # its lamp — the tell
    put(g, {28: [(16, 23)], 29: [(16, 23)], 30: [(16, 23)]}, 'a')   # chest bar
    return build("demo", g, specs=[(13, 10), (14, 10)])


# Ember's left half, traced cell for cell off the reference drawing and
# resampled from its 60-wide grid onto this cast's 24. Not authored in the
# usual sense and not run through the passes — see `traced`.
#
# `E` is the reference's red: both eyes and the inside of the mouth. It
# becomes `a` on the way out, so the live mood tint lands on them and the
# mouth doubles as the coal `breathe` starts its flame from.
_DRAGON = [
        '.......................H',
        '.............Sk........H',
        'S............Skk.......H',
        'H............SWk......SS',
        'HHD..........SWk.....SHW',
        'SHWk.........HWSk...HHSS',
        'SWWWSk.......HWSk.kkWHSW',
        '.kWWSSkk....SHWkDkBWWHWW',
        '.kkWWWHHkkk.SHWHkkWWHBSH',
        '..kSWWWWSkkkBHHHkSSWHDHH',
        '...kHHWWWkHkkHHHkHHWHSSH',
        '....kkHHSWHHSkkkkHWHHHHH',
        '.....kSHkWWHHSkkWHWWHHHH',
        '......kSkWWWWHSkWWWWHHHH',
        '.......kSWWWWWHHkWkkHBHW',
        '.......SkHWWWWWSDkHHHBSH',
        '.......SkSWWWWWWSDkHHHHH',
        '....HHSSSkSSWWWWHSDkHHHH',
        '....HWkWHSSkkHWWWSSkkHHW',
        '.....SkWHWWSkkWWWWSSkHkW',
        '....H.SHSWWSkkkkWHSSkHkW',
        '...HWkSHSWWWSkEEkSBBSkWk',
        '....HkkHHWWWDkEccEkkkkSW',
        '.....kkkHkWWHkEEcEkkkkSW',
        '......kkHSkWWSkESkkkkWBk',
        '....kkkkHHSkWWWBHSkkWkDW',
        '.......kSHSSkWWHHSkWWHWW',
        '.....HHkSHHSkkkkkkWWWWWW',
        '......kkkHHHSSkkkWWWWkkk',
        '........kkHHHHDkDWWHWWHk',
        '.........kSHHHSSHWWBWWWH',
        '..........kkSHHHHWSWkkWW',
        '............kHBBkWkkkkkH',
        '............kkSSkWWkWkkH',
        '.............kSHkWWWWkkH',
        '..............kkHkkWkkkH',
        '................HkkEkWSk',
        '................SSEEkkkk',
        '.................WEcESkk',
        '.................WkckEkk',
        '.................BWEEEES',
        '.................SWEcEEE',
        '..................kHcEcS',
        '..................kWEEcc',
        '...................WWWkc',
        '...................kBHWW',
        '....................kkkk',
        '.....................kkk',
]


def dragon():
    """Ember: the reference dragon's head, traced, mirrored and reddened.

    This one is a copy rather than a drawing of my own, and it is built
    differently from the rest of the cast because of that. `_DRAGON` is the
    left half of the reference lifted cell for cell — its grid was 60 wide
    against this cast's 48, so it is resampled, with teeth and eyes given
    priority in the vote: a tooth that loses a majority to the jaw around
    it is a tooth that is not there.

    What is deliberately *not* done to it:

      * No shading pass. The reference is already lit, from the upper left,
        and relighting a lit face flattens every plane it was drawn with.
      * No outline pass. There are no `#` cells for it to find — every cell
        here is already a tone or an outline.
      * No wings, no crest of my own, no brow of my own. All of that is in
        the reference and comes across with it.

    The one liberty is the mirror. The silhouette has to come back
    symmetric to the pixel and the reference is not quite, so the left half
    is mirrored over the right — and the mirrored side is stepped a rung
    darker, because a face lit the same from both sides reads as flat.
    """
    return traced("dragon", [r.replace('E', 'a') for r in _DRAGON])


if __name__ == '__main__':
    rows = dragon() if '--dragon' in sys.argv else (demo() if '--demo' in sys.argv else None)
    if rows is None:
        print(__doc__)
        raise SystemExit("nothing to draw: pass --demo or --dragon, or import this module")
    print(swift(rows))
    if '--png' in sys.argv:
        grey = [(.13, .15, .17), (.27, .29, .33), (.44, .46, .50),
                (.64, .67, .71), (.84, .86, .89), (.97, .98, .98)]
        ember = [(.169, .051, .047), (.286, .090, .071), (.431, .153, .098),
                 (.616, .251, .129), (.800, .408, .180), (.957, .729, .349)]
        png(sys.argv[sys.argv.index('--png') + 1], rows,
            ember if '--dragon' in sys.argv else grey,
            tint=(.98, .62, .16))
