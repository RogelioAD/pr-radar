#!/usr/bin/env python3
"""Draw a 48-cell mascot: author half of it, get a Swift literal back.

    python3 Scripts/mascot.py --demo            # a worked example, to stdout
    python3 Scripts/mascot.py --demo --png out.png

This is the pipeline the header comment in `Mascot.swift` refers to. It made
the October four and the Fantastic Four and it converted the OG cast; it is
committed because the rules it encodes were expensive to rediscover and are
invisible in the output.

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

THREE THINGS THE PASSES CANNOT DO, each with a helper below, all three
learned on the Fantastic Four:

  * `tone` — hand-place a rung, but never on the boundary. The shading pass
    is right for a hull and wrong for a face: with no edge close enough to
    matter it drops a wedge of shadow down the middle of a large flat
    plane, and a wedge down the middle of a face is a beard. But a tone
    painted right up to the edge is a cell `outline` will not ink — it
    converts `#` and nothing else — so the silhouette comes back with a gap
    in it. `tone` paints the inside and leaves the rim to the pass.

  * `seam` — a one-cell crack through the inside of a character, guarded
    the same way. For the one whose hide is slabs rather than skin, the
    light between them is the only part of him that can carry a mood.

  * `stamp` — paint a glyph over the *finished* rows. Everything else here
    comes back symmetric to the pixel, which is the whole point; a team
    badge with a `4` on it is the one thing that must not, because a
    mirrored 4 is a butterfly. It only touches cells that are already lit,
    so the silhouette cannot change and the symmetry test still holds.
"""

import math
import sys

# The cast's two formats. Forty-eight square is the bust everyone was drawn
# at; 96 by 144 is the full-length shelf, at four times the cell density and
# the same size on screen — at the mascot room's 54 points a 96-cell
# character puts one cell on one device pixel, which is as fine as the
# display can show and the point at which the staircase stops being visible.
W = H = 48
HALF = 24


def format(width, height):
    """Switch the module to a different grid. Everything here works in
    `W`/`H`/`HALF`, so a drawing says once what size it is and the passes
    follow."""
    global W, H, HALF
    W, H, HALF = width, height, width // 2
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


def tone(half, spans, ch):
    """Hand-place a rung, but never on the silhouette's boundary.

    See the header: a tone on the edge is a cell `outline` will not ink, so
    the drawing comes back with a gap in its edge wherever somebody painted
    hair or a cheek right up to it.
    """
    wide = len(half[0]) - 1
    lit = [[c != '.' for c in row] for row in half]

    def at(x, y):
        return 0 <= x <= wide and 0 <= y < len(half) and lit[y][x]

    for y, runs in spans.items():
        for a, b in runs:
            for x in range(max(0, a), min(wide, b) + 1):
                if half[y][x] == '.':
                    continue
                # The centre column's mirror is its own right-hand
                # neighbour, so it is never on the boundary however it
                # looks from this side of the drawing.
                if at(x - 1, y) and (at(x + 1, y) or x == wide) \
                        and at(x, y - 1) and at(x, y + 1):
                    half[y][x] = ch


def seam(half, points, ch='a'):
    """A crack: a one-cell path between points, through the inside only.

    Guarded against the boundary for the same reason `tone` is. Keep them
    the length of a slab — short ticks dotted about a face come out as
    stubble, and two of them crossing come out as a plus sign.
    """
    wide = len(half[0]) - 1
    lit = [[c != '.' for c in row] for row in half]

    def at(x, y):
        return 0 <= x <= wide and 0 <= y < len(half) and lit[y][x]

    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        steps = max(abs(x1 - x0), abs(y1 - y0), 1) * 2
        for i in range(steps + 1):
            t = i / steps
            x, y = round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t)
            if at(x - 1, y) and (at(x + 1, y) or x == wide) \
                    and at(x, y - 1) and at(x, y + 1):
                half[y][x] = ch


def stamp(rows, glyph, x0, y0, ch):
    """Paint a glyph over the finished rows — *after* the mirror.

    The one thing in this file that deliberately breaks symmetry, and the
    only safe way to put a `4` on something. It touches cells that are
    already lit and no others, so the silhouette is untouched and the
    mirror test still passes; only the colours come back asymmetric, which
    they are allowed to be.
    """
    out = [list(r) for r in rows]
    for j, line in enumerate(glyph):
        for i, c in enumerate(line):
            if c == '.':
                continue
            x, y = x0 + i, y0 + j
            if 0 <= x < W and 0 <= y < H and out[y][x] != '.':
                out[y][x] = ch
    return [''.join(r) for r in out]


# The team badge, for the shelf that wears one.
BADGE_FOUR = [
    '...##.',
    '..###.',
    '.#.##.',
    '#..##.',
    '######',
    '...##.',
    '...##.',
    '...##.',
]


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


def shade(full, cap=10, throw=3.2, dither=True):
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
            # Dithering is confined to the band where two rungs genuinely
            # meet, and at 96 cells it is turned off entirely: the checker
            # is a fixed one cell wide, so on art at four times the density
            # it covers a quarter of the area and reads as fabric texture
            # over the whole figure rather than as a soft edge.
            up = frac > 0.65 or (dither and frac > 0.35 and (x + y) % 2 == 0)
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


def build(name, half, specs=(), dither=True):
    """Half -> finished rows, mirrored, outlined, shaded."""
    print(f"-- {name}", file=sys.stderr)
    rows = [''.join(r) for r in
            specular(shade(outline(mirror(half)), dither=dither), specs)]
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
             'U': (.071, .125, .235), 'w': (.969, .973, .980),
             # The fixed trophy tones, which the traced shelf borrows for
             # hair and skin: a ramp is one hue, and a blond head on a blue
             # suit needs warm tones that are nobody's chassis.
             'o': (.937, .757, .259), 'n': (.706, .514, .114),
             'z': (.843, .561, .341), 'x': (.604, .373, .204),
             'e': (.804, .831, .878), 'm': (.561, .592, .651)}
    order = 'DSBHWX'

    # Sized off the art rather than off a constant. It was 48 squared for as
    # long as that was the only format there was, and a literal here is a
    # literal that has to be found and changed in step with every drawing.
    w = (len(rows[0]) + pad * 2) * scale
    h = (len(rows) + pad * 2) * scale
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


# ----------------------------------------------------------------- Christmas
#
# The December four, and the first cohort drawn with the `tone` pass doing
# most of the work rather than the shading one.
#
# The reason is the subject matter. Every character before these is one
# material — a hull, a sheet, a rind, bone — and one material is exactly what
# `shade` is for: fill the silhouette with `#`, let the distance field light
# it, done. A penguin is two materials in one outline and a Santa is four, and
# a distance field knows nothing about where the white starts.
#
# So they are all drawn the same way: fill the whole silhouette with `#` so
# the outline and the shading passes still have something to work on, and then
# `tone` the interior into whatever that part is actually made of. `tone`
# refuses to paint the boundary, which is the entire point — the rim stays `#`,
# comes back outlined and shaded off the character's own ramp, and the flat
# colour inside it reads as a plane rather than as a sticker.


def disc(cx, cy, rx, ry, top=None, bottom=None):
    """Row spans for the left half of an ellipse, clipped to the half's width.

    Everything here is round — a head, a penguin, a muzzle, a pom — and a
    circle authored as a column of hand-counted left edges is a circle with a
    flat spot in it that nobody can find.
    """
    out = {}
    lo = int(math.floor(cy - ry)) if top is None else top
    hi = int(math.ceil(cy + ry)) if bottom is None else bottom
    for y in range(max(0, lo), min(H - 1, hi) + 1):
        t = 1 - ((y - cy) / ry) ** 2
        if t <= 0:
            continue
        left = int(round(cx - rx * math.sqrt(t)))
        if left <= HALF - 1:
            out.setdefault(y, []).append((left, HALF - 1))
    return out


def pine():
    """Pine: the tree, and the only character in the cast with no face.

    That is the point of him rather than an omission. Every other mascot says
    what the app is doing with two eyes and one lit part; a tree has no eyes
    to say it with, so the lights say all of it — they are the tell, they are
    what the blink closes, and they are what the sweep walks. `Mascot.eyes`
    is empty for exactly this, and `Expression.frame` sends the eye pattern to
    the tell instead when it is.

    The garland is white and the bulbs hang off it, which is the one rule
    this shelf cost the most to learn: a tell painted straight onto a body of
    a similar hue disappears in the mood that matches it.

    A white string was not enough on its own here, because the clash is
    worse than his was. The tell goes green in the all-clear state and this
    character *is* green, and the first ramp's lightest rung came out at
    almost exactly `Health.good` — so the lights went out in the one mood
    that should read as everything being fine. The ramp is a real spruce
    now, dark enough that the brightest rung of the body is well below the
    dimmest rung of any accent. The white only has to separate the bulbs
    from each other.
    """
    g = blank()

    # The star. Four points: a vertical bar four columns wide with a bar
    # across it three rows thick. Three rather than two because a horizontal
    # arm two rows deep is the same spur the three-column rule forbids,
    # turned on its side — the outline pass inks both faces of it and the
    # point comes back as a seam.
    put(g, {y: [(left, 23)] for y, left in
            {0: 22, 1: 22, 2: 21, 3: 18, 4: 16, 5: 18, 6: 21, 7: 22}.items()}, 'a')

    # Three tiers, one left edge per row. Each starts further in than the row
    # above it ends, which is the notch the outline pass turns into the line
    # under a branch — and is the whole of what makes this read as a tree
    # rather than as a cone.
    put(g, {y: [(left, 23)] for y, left in
            {8: 21, 9: 20, 10: 19, 11: 18, 12: 18, 13: 17, 14: 16, 15: 15,
             16: 14, 17: 13,
             18: 18, 19: 17, 20: 16, 21: 15, 22: 14, 23: 14, 24: 13, 25: 12,
             26: 11, 27: 10, 28: 9,
             29: 14, 30: 13, 31: 12, 32: 11, 33: 10, 34: 10, 35: 9, 36: 8,
             37: 7, 38: 6, 39: 5, 40: 4}.items()}, '#')

    put(g, {y: [(21, 23)] for y in range(41, 45)}, '#')   # trunk
    put(g, {y: [(18, 23)] for y in range(45, 48)}, '#')   # the pot

    # Trunk and pot, off the trophy shelf's bronze. A ramp is one hue and
    # this one is spruce, whose darkest rung is not wood, it is shadow.
    tone(g, {y: [(21, 23)] for y in range(41, 45)}, 'x')
    tone(g, {y: [(18, 23)] for y in range(45, 48)}, 'z')

    # The garland: white, and the thing the glow runs along.
    tone(g, {13: [(15, 23)], 14: [(15, 23)]}, 'c')
    tone(g, {23: [(12, 23)], 24: [(12, 23)]}, 'c')
    tone(g, {35: [(7, 23)], 36: [(7, 23)]}, 'c')

    # And the bulbs, hung *under* it rather than drawn on it. Sitting on the
    # string they were three cells deep against the garland's two, so the
    # white only showed as slivers between them and each tier came back as
    # one orange bar. Hung below, the continuous line is the garland and the
    # bulbs are what is on it.
    #
    # Two on the top tier, three on the middle, four on the bottom — which is
    # what a string wound round a cone actually does, and is also what stops
    # the three tiers reading as three copies of one band.
    for top, columns in ((15, (16, 20)), (25, (13, 18, 22)), (37, (8, 13, 18, 22))):
        for left in columns:
            tone(g, {y: [(left, left + 2)] for y in range(top, top + 3)}, 'a')

    return build("pine", g, specs=[(19, 20), (20, 19), (20, 20)])


def pebble():
    """Pebble: the penguin, named for the stone a male gives the one he is
    courting, which is the only Christmas present in nature.

    One silhouette, not two. He was a circle on top of a bigger circle for
    two passes, which is the shape of a snowman and the shape of an owl and
    is not the shape of a bird that swims: a penguin is a single teardrop,
    narrow at the crown, barely pinched at the throat, widest two thirds of
    the way down, and tapering onto his feet. Drawn as stacked discs the head
    came out nearly as wide as the body and the waist between them read as a
    join rather than as a neck.

    The second thing the redraw is about is where the black goes. The first
    pass painted a white front and a white face and left the black to be
    whatever was round the outside, which is not how a penguin is marked: the
    black comes *over* him. It runs down the sides of the face past the eye
    to the throat, and down both sides of the belly, so the white is a panel
    he is wearing rather than the shape of him with a dark rim.

    He is also the reason the `tone` recipe in this section exists. A penguin
    shaded off one ramp is a grey penguin: the distance field puts the light
    at the top left and the dark at the bottom right, and a bird whose entire
    point is a white front on a black back comes back as neither. The two are
    painted and only the rim is left to the pass.
    """
    g = blank()

    # Two ellipses that overlap for four rows, so the waist between them is a
    # curve rather than a join. Still two calls, and the fix was never to
    # stop using them: the first pass had a head twenty-two cells across on a
    # body of twenty-five, which is a snowman whatever shape the outlines
    # are. The head is twenty here against a belly of twenty-six, and the
    # throat where they cross narrows to fourteen.
    #
    # Authored as a single run of left edges instead, he came back a
    # rounded-off box: ten rows of perfectly vertical edge down each side of
    # the head is a helmet, and nothing about the tones fixes it. A curve has
    # to come from something that knows it is a curve.
    put(g, disc(23.5, 13, 10, 11), '#')              # head
    put(g, disc(23.5, 33, 13, 13), '#')              # body
    put(g, {y: [(17, 23)] for y in range(20, 24)}, '#')   # the throat

    # Flippers, hung off the shoulder. The inner columns run further in than
    # the drawing needs, which is not sloppiness: the body narrows again
    # below the belly, and a flipper whose inner edge stopped at its own
    # outline met the body on a diagonal for the last few rows and came back
    # outlined all the way round — two loose wings floating beside him.
    #
    # Tapered a column per row at both ends rather than arriving at full
    # width in one. Squared off at the top it put a four-column step in the
    # outline at the shoulder, which on a bird that is supposed to be one
    # continuous teardrop is the one place a step cannot go.
    put(g, cols({7: (30, 35), 8: (28, 37), 9: (27, 38),
                 10: (26, 39), 11: (25, 40), 12: (24, 41)}), '#')

    # Feet, and bigger than a penguin's really are. Two small slabs tucked
    # under the belly read as something he is standing on rather than as part
    # of him; these come out past his sides where they can be seen.
    put(g, {y: [(13, 20)] for y in range(42, 47)}, '#')

    # The white, painted rather than lit: a face panel and a belly panel, each
    # well inside the silhouette so the black can come down past both.
    #
    # The face panel is the one shape here with straight sides, and that is
    # deliberate. An ellipse narrows exactly where the eyes are widest, so
    # either it swallowed the whole head — which turns the black into a cap
    # he is wearing — or an eye box ran off the white onto the cheek.
    #
    # Both panels are well inside their outline, and the second pass at this
    # drawing is mostly about how far inside. Drawn two cells from the edge
    # the white *was* the head and the black was a cap sitting on it; three
    # cells of cheek either side is what turns it back into a bird with a
    # white face.
    tone(g, {y: [(left, 23)] for y, left in
             {8: 20, 9: 18, 10: 17, 11: 17, 12: 17, 13: 17, 14: 17, 15: 17,
              16: 17, 17: 17, 18: 18, 19: 19, 20: 20}.items()}, 'W')
    tone(g, disc(23.5, 35, 7.5, 8.5), 'W')
    # And the black, which is most of him and all of it declared. The pass
    # would have lit the top left of the crown, the back and both flippers.
    tone(g, {y: [(15, 23)] for y in range(3, 10)}, 'D')
    tone(g, cols({c: (28, 43) for c in range(12, 16)}), 'D')
    # The whole flipper, top to bottom, and one rung lighter than the back it
    # hangs in front of. That step is the only thing separating them — two
    # lit cells side by side never get an outline between them. One rung and
    # no more: at two the flipper stops reading as a black wing catching the
    # light and starts reading as a panel let into his side.
    tone(g, cols({c: (25, 40) for c in range(8, 13)}), 'S')
    # The cheek: the black running down past the eye to the jaw. This is the
    # marking that was missing, and without it the crown reads as a cap he is
    # wearing rather than as the back of his own head.
    tone(g, cols({c: (9, 21) for c in range(14, 17)}), 'S')

    # Beak and feet. Off the trophy shelf's bronze rather than off his ramp:
    # the ramp is one hue and that hue is slate, which has no orange in it.
    tone(g, {16: [(21, 23)], 17: [(20, 23)], 18: [(20, 23)], 19: [(20, 23)]}, 'z')
    tone(g, {20: [(21, 23)]}, 'x')
    tone(g, {y: [(14, 19)] for y in range(43, 46)}, 'z')
    tone(g, {46: [(14, 19)]}, 'x')

    # The scarf: his tell, and the only thing on him the mood gets to colour.
    # Sat on the throat, which is where the drawing is narrowest — a scarf is
    # the one garment that explains a pinch rather than hiding one.
    tone(g, {22: [(14, 23)], 23: [(13, 23)]}, 'a')
    tone(g, {24: [(12, 23)], 25: [(12, 23)]}, 'N')
    tone(g, cols({c: (26, 32) for c in range(12, 16)}), 'N')
    tone(g, cols({c: (33, 35) for c in range(13, 16)}), 'M')

    # No specular. The one place the pass would want it is the crown, and a
    # white glint on a black head at this size is indistinguishable from an
    # eye — which this character already has two of, four rows below it.
    return build("pebble", g)


def dasher():
    """Dasher: the reindeer, drawn as a head because the antlers are the
    whole silhouette and a full-length deer at 48 cells has none.

    The antlers are the one place in this file where the three-row rule is
    broken on purpose. A beam sweeping up and out keeps to it the whole way,
    but the tine branching off it does not — it leaves the beam as a ten-row
    vertical step, which the outline pass inks as a ten-cell line. That line
    is the side of the tine. The rule is there to stop a *smooth* edge coming
    back as fringe, and a fork in an antler is not a smooth edge; it is a
    corner, and a corner is supposed to be a line.
    """
    g = blank()

    # The antler beam, as a column at a time. Thinking in columns is the only
    # way anything shaped along x ever works out here.
    #
    # Six and seven rows thick rather than the four they were first drawn at,
    # and the reason is the sweep rather than the look. A spur that thin is
    # all boundary: the outline pass inks every cell of it, the shading pass
    # finds no `#` left to shade, and a band that only lights chassis and
    # tell therefore dies halfway out and never reaches the tips.
    put(g, cols({17: (13, 20), 16: (11, 19), 15: (9, 17), 14: (7, 15),
                 13: (6, 13), 12: (5, 12), 11: (4, 11), 10: (3, 10),
                 9: (2, 9), 8: (2, 8), 7: (3, 8), 6: (4, 9), 5: (5, 10)}), '#')
    # And the tine off it, tapered at the tip so it is a point rather than a
    # post with a flat top.
    put(g, cols({11: (1, 11), 12: (0, 12), 13: (0, 13), 14: (1, 15)}), '#')

    put(g, disc(23.5, 27, 11.5, 10.5), '#')          # head
    put(g, disc(23.5, 38, 7.5, 7), '#')              # muzzle

    # Ears, out sideways from under the antlers.
    put(g, cols({4: (23, 26), 5: (22, 27), 6: (21, 27), 7: (21, 28),
                 8: (20, 28), 9: (20, 28), 10: (20, 28), 11: (20, 28)}), '#')

    # The blaze down the front of the face, and the pale muzzle. Both painted:
    # the pass lights from the upper left, and a deer's markings run down the
    # middle whatever the light is doing.
    tone(g, {y: [(20, 23)] for y in range(19, 33)}, 'W')
    tone(g, disc(23.5, 38, 5.5, 5), 'W')
    # The ears are darker inside than the head they sit on.
    tone(g, cols({c: (22, 26) for c in range(6, 11)}), 'S')

    # The nose: his tell, and the one thing anybody looks at on a reindeer.
    tone(g, {36: [(21, 23)], 40: [(21, 23)]}, 'N')
    tone(g, {y: [(20, 23)] for y in range(37, 40)}, 'a')

    # Above the eye rather than on it: the eye pass paints over whatever the
    # box covers, so a highlight inside it is a highlight nobody ever sees.
    return build("dasher", g, specs=[(17, 21), (18, 20), (18, 21)])


def nick():
    """Nick: Santa, redrawn, and the lesson of the redraw is that a beard is
    not a shape — it is three shapes with lines between them.

    The first pass had a nose, a beard and nothing else, and at badge size it
    read as a face in a hood with a soother in it. Nothing was wrong with the
    silhouette; what was missing was every *internal* edge. A moustache is
    what tells a beard from a bib, a shadow under the moustache is what tells
    a moustache from the beard it sits on, and a mouth is what stops the
    whole lower half being one cream mass. None of those change the
    silhouette by a single cell, and all of them are the difference between a
    character and a blob.

    The nose is twice the size it was for the same reason. It is one of his
    two tells and the other one is on top of his hat, so at 48 cells a nose
    drawn to scale is four cells of mood colour in the middle of all that
    white — which is not a nose, it is a mistake.
    """
    g = blank()

    put(g, disc(23.5, 4.5, 4.5, 4.5), '#')           # the bobble
    # The hat: one left edge per row, flaring to the brim.
    put(g, {y: [(left, 23)] for y, left in
            {6: 20, 7: 19, 8: 19, 9: 18, 10: 17, 11: 16, 12: 15, 13: 14,
             14: 13, 15: 12, 16: 11}.items()}, '#')
    put(g, {y: [(9, 23)] for y in range(16, 22)}, '#')    # the fur brim

    # The head. Not an ellipse: an ellipse under a hat brim comes to a point
    # where the two meet, so it hangs off him like an ornament instead of
    # being his head. It has to be wide where the brim is and round only at
    # the chin — but *curved* down the sides, which the first pass was not.
    # Straight from the brim to the cheekbone it came back as a box with a
    # hat on, and no amount of detail inside a box reads as a head.
    head = {20: 12, 21: 11, 22: 11, 23: 10, 24: 10, 25: 10, 26: 10, 27: 10,
            28: 10, 29: 11, 30: 11, 31: 12, 32: 13, 33: 14, 34: 15, 35: 17,
            36: 19}
    put(g, {y: [(left, 23)] for y, left in head.items()}, '#')

    # The beard, which is also the bottom of his silhouette. It leaves the
    # face at the cheekbone, flares past the jaw and tapers again.
    put(g, {y: [(left, 23)] for y, left in
            {30: 10, 31: 9, 32: 8, 33: 8, 34: 7, 35: 7, 36: 7, 37: 7, 38: 7,
             39: 7, 40: 8, 41: 8, 42: 9, 43: 10, 44: 12, 45: 14, 46: 17,
             47: 20}.items()}, '#')

    # Fur, brim, moustache and beard: all the same white, and none of it off
    # his ramp. His ramp is one hue and that hue is pillar-box red, so its
    # lightest rung is pink — which on a beard is not white hair, it is a
    # beard somebody has spilled something on.
    tone(g, disc(23.5, 4.5, 3.5, 3.5), 'c')
    tone(g, {y: [(9, 23)] for y in range(17, 21)}, 'c')
    tone(g, {21: [(10, 23)]}, 'e')                        # under the brim
    tone(g, {y: [(8, 23)] for y in range(27, 44)}, 'c')
    tone(g, {y: [(11, 23)] for y in range(44, 46)}, 'e')
    tone(g, {46: [(18, 23)]}, 'e')

    # Skin, painted back over the middle of the beard. Bronze off the trophy
    # shelf rather than a rung of his own, for the same reason the beard is
    # not pink. What is left of the white either side of it is the whiskers.
    #
    # It tracks the head's own edge at the forehead — one cell in, never two,
    # because `#` on this character shades to pillar-box red and a bare
    # column of it between the skin and the outline is a maroon stripe down
    # the side of his face. Below the eyes it pulls in much faster than the
    # head does, and the gap that opens up is the whiskers.
    tone(g, {y: [(left, 23)] for y, left in
             {20: 13, 21: 12, 22: 12, 23: 11, 24: 11, 25: 11, 26: 12, 27: 13,
              28: 14, 29: 15, 30: 16, 31: 16, 32: 17, 33: 18, 34: 19}.items()}, 'z')

    # The moustache: two sweeps of white under the nose, dropping at the
    # outer end. This is the line that turns the beard into a beard.
    tone(g, {35: [(14, 23)], 36: [(13, 23)], 37: [(13, 23)]}, 'c')
    tone(g, {38: [(14, 23)]}, 'e')      # and the shadow it casts on the beard

    # A mouth in the gap under it. Two rows of the ramp's own darkest rung,
    # which on a red character is maroon rather than black — a hole punched
    # in a beard with `outline` reads as damage.
    tone(g, {39: [(20, 23)], 40: [(21, 23)]}, 'D')

    # The tell: the bobble on his hat and his nose. Two spots a long way
    # apart, and neither of them a cheek — a patch of colour beside the nose
    # reads as one bar straight across his face, and moved far enough out to
    # stop doing that it is sitting on the beard.
    tone(g, {29: [(21, 23)], 34: [(21, 23)]}, 'N')
    tone(g, {y: [(20, 23)] for y in range(30, 34)}, 'a')
    # A solid core in a white rim rather than a core, a ring and a rim: at
    # four cells across, the middle ring is one cell wide and what comes back
    # is a button with a hole in it.
    tone(g, disc(23.5, 4.5, 2.5, 2.5), 'a')

    # On the hat: the only part of him the shading pass actually touches, and
    # so the only part a highlight can land on. The face and the beard are
    # painted, and `specular` will not overwrite a tone somebody placed.
    return build("nick", g, specs=[(16, 12), (17, 11), (17, 12)])


# The December four's own ramps, here rather than only in Swift so the preview
# shows what the app will. A character previewed in the demo greyscale is a
# character whose palette nobody looks at until it is already shipped.
RAMPS = {
    'pine':   [(.016, .055, .039), (.031, .102, .071), (.055, .157, .106),
               (.086, .227, .149), (.137, .318, .204), (.278, .467, .329)],
    'pebble': [(.043, .051, .075), (.086, .106, .149), (.149, .180, .247),
               (.251, .298, .388), (.871, .898, .937), (.988, .992, 1.00)],
    'dasher': [(.145, .090, .055), (.235, .149, .090), (.349, .227, .137),
               (.498, .337, .212), (.686, .525, .373), (.922, .843, .753)],
    'nick':   [(.188, .027, .047), (.310, .047, .071), (.455, .078, .102),
               (.627, .122, .145), (.800, .306, .306), (.969, .722, .698)],
}

CHRISTMAS = ['pine', 'pebble', 'dasher', 'nick']


if __name__ == '__main__':
    grey = [(.13, .15, .17), (.27, .29, .33), (.44, .46, .50),
            (.64, .67, .71), (.84, .86, .89), (.97, .98, .98)]
    ember = [(.169, .051, .047), (.286, .090, .071), (.431, .153, .098),
             (.616, .251, .129), (.800, .408, .180), (.957, .729, .349)]

    # The shelf, which is four characters rather than one. `--png` takes a
    # directory here instead of a file, because four drawings do not fit in
    # one path.
    if '--christmas' in sys.argv:
        out = sys.argv[sys.argv.index('--png') + 1] if '--png' in sys.argv else None
        for name in CHRISTMAS:
            rows = globals()[name]()
            print(f"// {name}")
            print(swift(rows))
            if out:
                png(f"{out.rstrip('/')}/{name}.png", rows, RAMPS[name],
                    tint=(.98, .62, .16))
        raise SystemExit(0)

    rows = dragon() if '--dragon' in sys.argv else (demo() if '--demo' in sys.argv else None)
    if rows is None:
        print(__doc__)
        raise SystemExit("nothing to draw: pass --demo, --dragon or --christmas, "
                         "or import this module")
    print(swift(rows))
    if '--png' in sys.argv:
        png(sys.argv[sys.argv.index('--png') + 1], rows,
            ember if '--dragon' in sys.argv else grey,
            tint=(.98, .62, .16))
