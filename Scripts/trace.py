#!/usr/bin/env python3
"""Import the supplied sprite sheet onto the cast's 96 x 144 grid.

This is the `traced()` path, which the dragon already uses: art somebody
else drew, resampled onto this app's grid and *not* run through the outline
or the shading pass. Both passes exist to turn a flat authored half into a
lit drawing, and the reference is already lit — relighting it would flatten
every plane it was drawn with, and outlining it would put a black rim round
art that has its own edges.

Two things are decided here rather than copied:

  * Which colours become the **tell**. A traced figure keeps the
    reference's own palette, which means by default nothing on it moves
    when the app's state changes — and a mascot that cannot show a mood is
    a drawing. In both forms the reds are the fire, so the reds become the
    accent: the outer flame on the powered one, the flame in his hand on
    the civilian one.

  * The six **chassis rungs**, sampled from the reference's own dominant
    hue by luminance. The body then keeps the colour it was drawn in while
    still being a ramp the rest of the app understands.
"""
import colorsys
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import readpng


HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, '..', 'Art')
SRC = os.path.join(ART, 'human-torch.png')
OUT = os.environ.get('TRACE_OUT', '/tmp/')

CELLS_W, CELLS_H = 96, 144

# Both forms are anchored at the **feet** and scaled by the same amount, and
# centred on the torso rather than on the bounding box.
#
# Both of those were wrong in the first import and both were wrong in the
# same way: measured off the bounding box, the powered form is wider and
# taller than the civilian one, because it has flame trailing off it in
# every direction. Centring on that box put him a full six cells left of
# where he stands in his suit, and fitting it to the box made him shorter to
# make room for the fire above his head. He swapped forms by jumping
# sideways and shrinking.
#
# Both forms are anchored on the **head**, horizontally and vertically, and
# scaled by the same amount.
#
# The head rather than the feet, and that took two goes to get right. Feet
# are the landmark that sounds correct — he is standing in the same place
# either way — but the powered drawing is crouched into its pose, so its
# head sits two dozen source pixels lower. Anchored at the floor, his face
# moved down eleven cells when he lit up, which put the app's eye boxes on
# empty air above his head. There is a test for exactly that now.
#
# Anchored at the head his feet rise instead, which is not a compromise:
# he flies. Flaming on and lifting off the ground is what the character
# does, and it falls out of aligning the one thing an eye actually tracks.
#
# Both landmarks are measured rather than guessed: `centre` is the middle of
# the first skull-width run of pixels, `top` is the row it starts on.
SOURCE_TOP = 28         # the civilian figure's full height sets the scale
BASELINE = 301
HEAD_ROW = 8            # the cell row both heads start on

# Per figure: which sheet it is on, where its head is in that sheet, and —
# for a sheet that is not the Human Torch one — how tall its figure is and
# what row its head should land on.
#
# A second sheet needs all of that because nothing about the first one
# generalises: it was drawn at 275 pixels tall with four rows of headroom,
# and the Invisible Woman sheet is 125 tall with her hair touching the top
# edge. Scaling her by the Torch sheet's numbers would put her chin at the
# bottom of the frame.
FIGURES = {
    'fire': dict(centre=159, top=60),
    'suit': dict(centre=506, top=36),
    'sue':  dict(sheet='invisible-woman.png', centre=81, top=0,
                 source_top=0, baseline=125, head_row=2, palette='sue'),
}


def is_bg(p):
    r, g, b, a = p
    return a < 24 or (r > 238 and g > 238 and b > 238)


def family(r, g, b):
    """Hue bucket, perceptual luminance, saturation.

    Luma rather than HLS lightness, which was the first version and was
    quietly wrong: lightness is (max + min) / 2, so pure red and pure
    yellow both score exactly 0.5. Sampling a ramp by it gathered six tones
    that were all the same brightness and the figure came back flat, and
    separating skin from flame by it could not work at all.
    """
    hue, _, sat = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    deg = hue * 360
    if sat < 0.16:
        return 'grey', lum, sat
    if deg < 16 or deg >= 345:
        return 'red', lum, sat
    if deg < 44:
        return 'orange', lum, sat
    if deg < 70:
        return 'yellow', lum, sat
    if deg < 190:
        return 'green', lum, sat
    if deg < 262:
        return 'blue', lum, sat
    return 'pink', lum, sat


def resample(px, scale, origin_x, origin_y):
    """Area-average the source into the 96 x 144 grid.

    Averaging rather than nearest-neighbour: the reference is anti-aliased
    and roughly twice the grid's resolution, so picking one source pixel per
    cell throws away half the drawing and turns a shaded limb into a
    stair-stepped one. Background does not get a vote — averaged in, it
    washes every edge pixel toward white and the figure comes back with a
    halo baked into it.
    """
    grid = []
    for cy in range(CELLS_H):
        row = []
        for cx in range(CELLS_W):
            sx0 = origin_x + cx / scale
            sx1 = origin_x + (cx + 1) / scale
            sy0 = origin_y + cy / scale
            sy1 = origin_y + (cy + 1) / scale
            r = g = b = 0.0
            lit = total = 0
            for sy in range(int(sy0), max(int(sy0) + 1, int(sy1))):
                for sx in range(int(sx0), max(int(sx0) + 1, int(sx1))):
                    if not (0 <= sy < len(px) and 0 <= sx < len(px[0])):
                        continue
                    total += 1
                    p = px[sy][sx]
                    if is_bg(p):
                        continue
                    lit += 1
                    r += p[0]; g += p[1]; b += p[2]
            if total == 0 or lit * 2 < total:
                row.append(None)
            else:
                row.append((r / lit, g / lit, b / lit))
        grid.append(row)
    return grid


def ramp_from(grid, hue):
    """Six rungs, sampled from the reference's own dominant hue.

    By luminance percentile rather than by clustering: the drawing already
    has a ramp in it — somebody chose those tones — and the job here is to
    find it, not to invent a new one.
    """
    tones = []
    for row in grid:
        for cell in row:
            if cell is None:
                continue
            fam, lum, sat = family(*cell)
            if fam in hue:
                tones.append((lum, cell))
    tones.sort(key=lambda t: t[0])
    if not tones:
        return [(0.1, 0.1, 0.1)] * 6
    # Averaged within each sixth rather than one pixel picked from it. A
    # single sample is a single pixel of somebody's anti-aliasing, and the
    # first go at this produced a blue ramp with a violet rung in the middle
    # of it.
    out = []
    for i in range(6):
        lo = int(len(tones) * i / 6)
        hi = max(lo + 1, int(len(tones) * (i + 1) / 6))
        band = [c for _, c in tones[lo:hi]]
        out.append(tuple(sum(c[j] for c in band) / len(band) / 255
                         for j in range(3)))
    return out


RUNGS = 'DSBHW'   # deep -> light; X is the sixth and is hand-placed only


def classify(cell, kind, ramp_lums):
    """One averaged colour -> one slot."""
    if cell is None:
        return '.'
    fam, lum, sat = family(*cell)
    hue, _, _ = colorsys.rgb_to_hls(cell[0] / 255, cell[1] / 255, cell[2] / 255)
    deg = hue * 360

    if kind == 'fire':
        # The reds are the outer flame and become the tell. The body keeps
        # its own oranges and yellows as chassis rungs, so he still has
        # shading — remapped wholesale to the three accent strengths he came
        # back as a flat silhouette, because three tones cannot carry a body.
        if fam == 'red':
            return 'a' if lum > 0.42 else ('N' if lum > 0.3 else 'M')
        if fam == 'grey' and lum < 0.3:
            return 'k'
    else:
        # The civilian suit. Hair, skin and the flame in his raised fist are
        # all warm, and the three are separated on hue and luminance taken
        # off the reference itself rather than on guessed thresholds: the
        # hair runs hue 30-50 at full saturation, the skin sits at hue 10-20
        # and half again as bright, and the flame is the only thing that is
        # both that saturated and that dark.
        #
        # Hair and skin are painted in the fixed trophy slots — gold and
        # bronze — rather than off his ramp. A ramp is one hue and his is
        # the blue of the suit; these are the only fixed warm tones the
        # alphabet has, and three rungs of gold is exactly what blond hair
        # needs.
        if 25 <= deg <= 65 and sat > 0.7 and lum > 0.45:
            return 'c' if lum > 0.80 else ('o' if lum > 0.62 else 'n')
        if deg <= 25 or deg >= 340:
            if sat > 0.85 and lum < 0.48:
                return 'a' if lum > 0.34 else 'N'      # the flame he holds
            if lum > 0.34:
                return 'z' if lum > 0.60 else 'x'      # skin
            return 'k'
        if fam == 'grey' and lum < 0.26:
            return 'k'

    # Everything else lands on the nearest rung by luminance.
    best, gap = 'H', 99.0
    for letter, target in zip(RUNGS, ramp_lums):
        if abs(lum - target) < gap:
            best, gap = letter, abs(lum - target)
    return best


# The team badge, stamped on the chest of both forms after the trace.
#
# The powered form has fire all over it and the civilian form has a flame in
# his raised fist, so both already carry a tell — but the fist is a long way
# from his face, and the header lockup crops to the head. A character whose
# tell is outside its own crop is a character the header cannot show a mood
# on, which is the entire reason a tell exists. The badge is central, it is
# on both forms in the same place, and it is what makes four separate
# drawings read as one team.
FOUR = [
    '..###.',
    '.####.',
    '##.##.',
    '#..##.',
    '######',
    '...##.',
    '...##.',
]
CHEST = {'suit': (45, 32), 'fire': (44, 28), 'sue': (44, 36)}


def stamp(rows, kind):
    out = [list(r) for r in rows]
    x0, y0 = CHEST[kind]
    for j, line in enumerate(FOUR):
        for i, c in enumerate(line):
            if c == '.':
                continue
            x, y = x0 + i, y0 + j
            if 0 <= x < CELLS_W and 0 <= y < CELLS_H and out[y][x] != '.':
                out[y][x] = 'a'
    return [''.join(r) for r in out]


def trace(kind):
    spec = FIGURES[kind]
    w, h, px = readpng.read(os.path.join(ART, spec.get('sheet', 'human-torch.png')))
    top = spec.get('source_top', SOURCE_TOP)
    scale = (CELLS_H - 4) / (spec.get('baseline', BASELINE) - top)
    origin_y = spec['top'] - spec.get('head_row', HEAD_ROW) / scale
    origin_x = spec['centre'] - (CELLS_W / 2) / scale
    grid = resample(px, scale, origin_x, origin_y)

    if spec.get('palette') == 'sue':
        return sue(grid), SUIT_RAMP

    hue = ('orange', 'yellow') if kind == 'fire' else ('blue',)
    ramp = ramp_from(grid, hue)
    ramp_lums = [0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2] for c in ramp[:5]]

    rows = [''.join(classify(cell, kind, ramp_lums) for cell in row)
            for row in grid]
    return stamp(rows, kind), ramp


# The suit, as the Human Torch sheet has it. Shared on purpose: the two
# sheets were drawn by different hands for different games and her navy is
# four times darker than his blue. Sampled from her own art she comes out a
# silhouette, and two people in the same uniform in visibly different
# uniforms is not a team.
SUIT_RAMP = [(0.106, 0.176, 0.455), (0.125, 0.259, 0.545), (0.133, 0.306, 0.671),
             (0.133, 0.357, 0.753), (0.161, 0.404, 0.808), (0.173, 0.514, 0.894)]


def sue(grid):
    """The Invisible Woman sheet, which needs its own rules.

    Her suit's rungs are **stretched** across her own range rather than read
    off absolute luminance. Everything else here maps a tone onto the
    nearest rung by brightness, which works while the art is lit the way
    this cast is lit; her sheet runs from 6% to 28%, so every cell of it
    lands on the bottom rung and she comes back as a silhouette.
    
    Stretched linearly, and not by percentile — which was the first attempt
    and collapsed. Her art is three heavily repeated tones and very little
    else, so half the pixels share one value: cut into six by rank, four of
    the cuts land on that same value and every one of those pixels still
    gets the same rung. Spreading her range end to end keeps the few
    highlights she does have as highlights.
    """
    # Through `family`, so this is the same 0-to-1 luminance the comparison
    # below uses. Computed inline it came out on the 0-to-255 scale, every
    # cell read as darker than the darkest cut, and she rendered as one flat
    # navy shape — which looked exactly like art that was simply flat.
    blues = sorted(family(*c)[1] for row in grid for c in row
                   if c is not None and family(*c)[0] == 'blue')
    # Trimmed ends, so one stray anti-aliased pixel does not set the range.
    lo = blues[int(len(blues) * 0.02)] if blues else 0.0
    hi = blues[int(len(blues) * 0.98)] if blues else 1.0
    span = max(0.01, hi - lo)

    rows = []
    for row in grid:
        line = ''
        for cell in row:
            if cell is None:
                line += '.'
                continue
            fam, lum, sat = family(*cell)
            hue, _, _ = colorsys.rgb_to_hls(*[v / 255 for v in cell])
            deg = hue * 360
            if 25 <= deg <= 70 and sat > 0.25 and lum > 0.34:
                line += 'c' if lum > 0.74 else ('o' if lum > 0.50 else 'n')
            elif (deg <= 25 or deg >= 330) and lum > 0.40 and sat > 0.15:
                line += 'z' if lum > 0.58 else 'x'
            elif lum < 0.055:
                line += 'k'
            else:
                at = int((lum - lo) / span * len(RUNGS))
                line += RUNGS[max(0, min(len(RUNGS) - 1, at))]
        rows.append(line)
    return stamp(rows, 'sue')


if __name__ == '__main__':
    from mascot import png, swift
    import mascot
    mascot.format(CELLS_W, CELLS_H)
    for kind in ('fire', 'suit', 'sue'):
        rows, ramp = trace(kind)
        open(OUT + f'traced-{kind}.txt', 'w').write(swift(rows))
        lit = sum(1 for r in rows for c in r if c != '.')
        print(f'{kind}: {lit} lit cells, ramp '
              + ' '.join(f'#{int(c[0]*255):02x}{int(c[1]*255):02x}{int(c[2]*255):02x}'
                         for c in ramp))
        png(OUT + f'traced-{kind}.png', rows, ramp, scale=5, tint=(0.95, 0.35, 0.12))
