import Foundation

extension Mascot {

    /// The glass this character has, as a bounding box, or nil for the one who
    /// has none.
    ///
    /// Derived from the art rather than declared, so moving a visor by a pixel
    /// cannot leave a beam sweeping the wrong rectangle.
    public var glassBounds: (origin: Point, width: Int, height: Int)? {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for point in sprite.litPoints {
            guard let slot = sprite[point.x, point.y],
                  slot == .visor || slot == .visorLit else { continue }
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        guard minX <= maxX else { return nil }
        return (Point(minX, minY), maxX - minX + 1, maxY - minY + 1)
    }

    /// The rows the character actually occupies.
    ///
    /// The sweeps that travel the whole body need this rather than the grid's
    /// full height: a band walking 0..<48 spends a third of its cycle in the
    /// empty rows above and below a character, which reads as the animation
    /// stopping. Derived, so it cannot fall out of step with a redraw.
    public var litRows: ClosedRange<Int> {
        let ys = sprite.litPoints.map(\.y)
        return (ys.min() ?? 0)...(ys.max() ?? 0)
    }

    /// The rows a travelling band can actually light.
    ///
    /// Narrower than `litRows`, and the difference matters. A band only
    /// touches chassis and tell — it deliberately leaves the outline alone,
    /// because an outline that flashes stops reading as an edge. Plenty of
    /// silhouettes open and close on rows that are *nothing but* outline:
    /// Nimbus is a rounded cloud whose first three and last three rows are
    /// pure `k`, so a band parked there painted nothing at all and the sweep
    /// appeared to stop for a sixth of its cycle.
    public var sweepRows: ClosedRange<Int> {
        let ys = sprite.litPoints.filter {
            guard let slot = sprite[$0.x, $0.y] else { return false }
            return slot.isChassis || isTell(slot)
        }.map(\.y)
        guard let low = ys.min(), let high = ys.max() else { return litRows }
        return low...high
    }

    /// The character with a mood applied and one frame of its own idling.
    ///
    /// Order matters and is the argument. The tic runs first because it moves
    /// parts of the body the eyes sit on; the eyes are drawn next; the sweep
    /// runs last so the beam passes *over* a lit eye and flares it, rather
    /// than under it where the eye would swallow the beam whole.
    public func frame(eyes pattern: EyePattern,
                      frame: Int = 0,
                      sweeping: Bool = false) -> Sprite {
        var grid = sprite
        tic(&grid, frame: frame)
        for box in eyes { drawEye(&grid, at: box, pattern: pattern) }
        if sweeping { sweep(&grid, frame: frame) }
        return grid
    }

    // MARK: - Eyes

    private func drawEye(_ grid: inout Sprite, at box: Point, pattern: EyePattern) {
        let n = eyeSize
        switch pattern {
        case .open, .wide:
            // Startled is the same lens one pixel bigger all round, not a
            // different drawing — an eye that changes shape when surprised
            // reads as a different character.
            let pad = pattern == .wide ? 1 : 0
            let m = n + pad * 2, cut = max(1, m / 4)
            for j in 0..<m {
                for i in 0..<m where !isCorner(i, j, of: m, cut: cut) {
                    grid.plot(box.x - pad + i, box.y - pad + j, eyeInk)
                }
            }
            let g = max(2, n / 3)
            for j in 0..<(g - 1) {
                for i in 0..<g { grid.plot(box.x + 1 + i, box.y + 1 + j, .light) }
            }
        case .shut:
            // Overhangs the box by a pixel each side: a closed lid is wider
            // than the eye it covers.
            let mid = n / 2
            for i in -1...n {
                grid.plot(box.x + i, box.y + mid, eyeInk)
                grid.plot(box.x + i, box.y + mid + 1, eyeInk)
            }
        case .glance:
            let off = n / 3
            for j in 1..<(n - 1) {
                for i in off..<n { grid.plot(box.x + i, box.y + j, eyeInk) }
            }
            grid.plot(box.x + off + 1, box.y + 2, .light)
        case .dead:
            for i in 0..<n {
                grid.plot(box.x + i, box.y + i, eyeInk)
                grid.plot(box.x + i + 1, box.y + i, eyeInk)
                grid.plot(box.x + n - 1 - i, box.y + i, eyeInk)
                grid.plot(box.x + n - i, box.y + i, eyeInk)
            }
        }
    }

    private func isCorner(_ i: Int, _ j: Int, of n: Int, cut: Int) -> Bool {
        i + j < cut || (n - 1 - i) + j < cut
            || i + (n - 1 - j) < cut || (n - 1 - i) + (n - 1 - j) < cut
    }

    // MARK: - Idling

    /// The small thing each character does whatever the mood is, so nobody is
    /// ever perfectly still.
    private func tic(_ grid: inout Sprite, frame: Int) {
        let f = abs(frame)
        switch id {
        case .blip:
            let lit: Slot = f % 8 < 4 ? .accent : .accentDim
            repaintAccent(&grid, x: 20..<28, y: 1..<5, with: lit)
        case .scoot:
            // A glare crossing the visor on the diagonal, which is what a
            // curved faceplate does under a moving light.
            let gx = 10 + (f * 2) % 34
            for i in 0..<11 where grid[gx - i, 11 + i] == .visor {
                grid.plot(gx - i, 11 + i, .visorLit)
            }
        case .wobble:
            // Six hull lights, one lit at a time, going round. This is the
            // rotation a radar actually is, and it is his whole tell.
            let on = (f / 2) % 6
            for (index, x0) in [2, 9, 16, 29, 36, 43].enumerated() {
                for y in 23..<26 {
                    for x in x0..<(x0 + 3) where grid[x, y] == .accent || grid[x, y] == .accentDim {
                        grid.plot(x, y, index == on ? .accent : .accentDim)
                    }
                }
            }
        case .bloop:
            // Antennae lean together rather than independently: two stalks
            // waving out of phase reads as broken, not alive.
            let lean = [0, 1, 1, 0, -1, -1][f % 6]
            if lean != 0 {
                let row = (0...8).map { y in (0..<grid.width).map { grid[$0, y] } }
                for y in 0...8 {
                    for x in 0..<grid.width {
                        let from = x - lean
                        grid[x, y] = (from >= 0 && from < grid.width) ? row[y][from] : nil
                    }
                }
            }
            let pulse: Slot = f % 6 < 3 ? .accent : .accentDim
            repaintAccent(&grid, x: 0..<grid.width, y: 0..<4, with: pulse)

        case .boo:
            // The hem drifts, the way a sheet does. Only the bottom eight
            // rows move: shifting the whole of him is a slide across the
            // badge rather than a character standing still and billowing.
            let drift = [0, 1, 1, 0, -1, -1][f % 6]
            if drift != 0 { shift(&grid, rows: 39..<grid.height, by: drift) }
            repaintAccent(&grid, x: 0..<grid.width, y: 39..<grid.height,
                          with: f % 4 < 2 ? .accent : .accentDim)

        case .flit:
            // The ears swivel, which is the one thing a bat is always doing.
            let turn = [0, 0, 1, 1, 0, 0, -1, -1][f % 8]
            if turn != 0 { shift(&grid, rows: 2..<11, by: turn) }

        case .gourd:
            // The candle. Never fully out and never steady: two rungs of
            // guttering, which is what a flame behind a carving looks like.
            let flame: Slot = [Slot.accent, .accent, .accentMid, .accent,
                               .accentDim, .accentMid][f % 6]
            repaintAccent(&grid, x: 0..<grid.width, y: 0..<grid.height, with: flame)

        case .rattle:
            // His jaw. Two rows, so it reads as chattering rather than as the
            // whole skull nodding.
            if f % 4 < 2 { shift(&grid, rows: 20..<24, by: 0, down: 1) }

        // The original cast. Each keeps the one thing it always did — these
        // are the idles the 16-cell art was drawn around, at three times the
        // coordinates.
        case .pip:
            repaintAccent(&grid, x: 18..<30, y: 0..<6,
                          with: f % 8 < 4 ? .accent : .accentDim)

        case .byte:
            // The ears, which is the whole of him. They twitch rather than
            // blink: dark eyes leave nothing else on his face to move.
            let twitch = [0, 0, 1, 1, 0, 0, -1, -1][f % 8]
            if twitch != 0 { shift(&grid, rows: 0..<12, by: twitch) }

        case .widget:
            // The power LED only. The mouth bar is the tell you read, and a
            // mouth that flashes reads as a fault rather than as a face.
            repaintAccent(&grid, x: 30..<42, y: 27..<30,
                          with: f % 6 < 3 ? .accent : .accentDim)

        case .nimbus:
            repaintAccent(&grid, x: 0..<grid.width, y: 23..<28,
                          with: f % 10 < 5 ? .accent : .accentDim)
        }
    }

    /// Slides a band of rows sideways, or down, leaving what it vacates empty.
    ///
    /// Shared by the four idles that move a part rather than recolour one.
    /// Each was a copy of the alien's antenna shuffle before this, and three
    /// copies of a loop that reads a row into an array and writes it back one
    /// place over is three chances to get the bounds wrong.
    private func shift(_ grid: inout Sprite, rows: Range<Int>, by dx: Int, down dy: Int = 0) {
        let band = rows.clamped(to: 0..<grid.height)
        let source = band.map { y in (0..<grid.width).map { grid[$0, y] } }
        for (index, y) in band.enumerated() {
            for x in 0..<grid.width {
                let fromX = x - dx, fromRow = index - dy
                grid[x, y] = (fromX >= 0 && fromX < grid.width
                              && fromRow >= 0 && fromRow < source.count)
                    ? source[fromRow][fromX] : nil
            }
        }
    }

    /// Four sweeps, one per character, and each one is theirs.
    ///
    /// Deriving the axis from the shape of the glass was the mistake: it
    /// collapsed a helmet scanning downward and a saucer's searchlight into
    /// the same beam going across, because all three happen to have a visor
    /// wider than it is tall. The kind is declared on the character now.
    ///
    /// What they share is that a real beam turns one way and never stops. All
    /// four wrap, so there is no frame without a sweep in it.
    private func sweep(_ grid: inout Sprite, frame: Int) {
        switch sweep {
        case .visor:   glassBeam(&grid, frame: frame, down: false)
        case .hud:     glassBeam(&grid, frame: frame, down: true)
        case .beam:    searchlight(&grid, frame: frame)
        case .psi:     rings(&grid, frame: frame)
        case .wisp:    shimmer(&grid, frame: frame, rising: true)
        case .echo:    sonar(&grid, frame: frame)
        case .flicker: candle(&grid, frame: frame)
        case .marrow:  spine(&grid, frame: frame)
        }
    }

    /// Boo, with nothing to put a beam on.
    ///
    /// A ghost is the one shape a beam cannot cross, because there is no
    /// surface for it to cross — so the light goes *through* him instead: a
    /// band rising up the body, brightening whatever it passes and flaring
    /// the mouth and the hem as it reaches them.
    ///
    /// Confined to the rows he actually occupies. A band walking the full 48
    /// spends a third of its cycle in empty space, which reads as the app
    /// having stopped rather than as a ghost.
    ///
    /// The trail wraps rather than running off the end, the same bargain
    /// `glassBeam` makes: his last row is the hem's outline and has nothing
    /// on it to light, so a trail that stopped there left one frame in every
    /// cycle with no sweep in it at all. Wrapped, the next shimmer is already
    /// entering at the top as the last one leaves — which is what a rising
    /// shimmer looks like anyway.
    private func shimmer(_ grid: inout Sprite, frame: Int, rising: Bool) {
        let rows = sweepRows
        let span = max(1, rows.count)
        let step = abs(frame) % span
        for band in 0...3 {
            let offset = rising ? (step - band + span) % span : (step + band) % span
            let y = rising ? rows.upperBound - offset : rows.lowerBound + offset
            guard rows.contains(y) else { continue }
            paintRow(&grid, y, lead: band == 0, strength: band == 0 ? 2 : 1)
        }
    }

    /// Flit's echolocation: three arcs thrown down and out of the muzzle, the
    /// nearest bright and the far ones fading.
    ///
    /// A cone rather than a ring — a bat calls forward, and a full circle
    /// would put the same pulse behind his own wings where it reads as a halo.
    private func sonar(_ grid: inout Sprite, frame: Int) {
        let apexX = Double(grid.width) / 2, apexY = 25.0
        for index in 0..<3 {
            let radius = (Double(abs(frame)) * 1.4 + Double(index) * 7)
                .truncatingRemainder(dividingBy: 21) + 4
            let tone: Slot = radius < 13 ? .accentMid : .accentDim
            var angle = 0.45
            while angle < 2.70 {
                let x = Int((apexX + cos(angle) * radius * 1.3).rounded())
                let y = Int((apexY + sin(angle) * radius).rounded())
                if grid[x, y] == nil {
                    grid.plot(x, y, tone)
                } else {
                    brighten(&grid, x, y, by: radius < 13 ? 2 : 1)
                }
                angle += 0.05
            }
        }
    }

    /// Gourd is lit from the inside, so his sweep is the candle rather than
    /// anything crossing him: the carving pulses and the light it throws
    /// creeps out into the rind around it.
    ///
    /// The spill is drawn from the *carved* cells rather than from a point,
    /// so it comes out of the eyes and the grin — which is where the light in
    /// a lantern actually leaves.
    private func candle(_ grid: inout Sprite, frame: Int) {
        let step = abs(frame) % 6
        let carved: [Slot] = [.light, .accent, .accent, .accentMid, .accent, .light]
        let spill = [2, 1, 1, 0, 1, 2][step]
        let lit = grid.litPoints.filter { isTell(grid[$0.x, $0.y]) }
        for point in lit { grid.plot(point.x, point.y, carved[step]) }
        guard spill > 0 else { return }
        for point in lit {
            for dy in -spill...spill {
                for dx in -spill...spill where abs(dx) + abs(dy) <= spill {
                    brighten(&grid, point.x + dx, point.y + dy, by: spill)
                }
            }
        }
    }

    /// Rattle, read from the top down: a pulse that stops on each rib rather
    /// than sliding past them.
    ///
    /// Stepping is the whole difference between this and Boo's shimmer, which
    /// is otherwise the same band on the same axis. A smooth one down a
    /// skeleton reads as a photocopier; stopping at each bone reads as
    /// something being counted.
    private func spine(_ grid: inout Sprite, frame: Int) {
        let rows = sweepRows
        let stops = 9
        // Held for two frames apiece, so each stop is seen rather than
        // flicked through.
        let at = (abs(frame) / 2) % stops
        let head = rows.lowerBound + at * rows.count / stops
        for band in 0..<3 {
            let y = head + band
            guard rows.contains(y) else { continue }
            paintRow(&grid, y, lead: band == 0, strength: band == 0 ? 2 : 1)
        }
    }

    /// One row of a travelling band: the tell flares, the chassis brightens,
    /// and nothing else is touched.
    private func paintRow(_ grid: inout Sprite, _ y: Int, lead: Bool, strength: Int) {
        for x in 0..<grid.width {
            guard let slot = grid[x, y] else { continue }
            if isTell(slot) {
                grid.plot(x, y, lead ? .light : .accent)
            } else if slot.isChassis {
                brighten(&grid, x, y, by: strength)
            }
        }
    }

    func isTell(_ slot: Slot?) -> Bool {
        switch slot {
        case .accent, .accentMid, .accentDim: return true
        default: return false
        }
    }

    /// Blip across his HUD, Scoot down the inside of his helmet. The same
    /// beam on two axes, each with four steps of trail behind the head, and
    /// each drawn after the eyes so it passes *over* them and flares one as
    /// it crosses rather than sliding underneath it.
    private func glassBeam(_ grid: inout Sprite, frame: Int, down: Bool) {
        guard let glass = glassBounds else { return }
        let span = down ? glass.height : glass.width
        let head = (abs(frame) % 18) * span / 18
        for band in stride(from: 4, through: 0, by: -1) {
            let at = ((head - band) % span + span) % span
            let tone: Slot = band == 0 ? .accentMid : .accentDim
            if down {
                let y = glass.origin.y + at
                for x in glass.origin.x..<(glass.origin.x + glass.width) {
                    lightGlass(&grid, x, y, tone: tone, lead: band == 0)
                }
            } else {
                let x = glass.origin.x + at
                for y in glass.origin.y..<(glass.origin.y + glass.height) {
                    lightGlass(&grid, x, y, tone: tone, lead: band == 0)
                }
            }
        }
    }

    /// Wobble's tractor beam, swinging through an arc under the hull like a
    /// searchlight rather than hanging straight down.
    ///
    /// Drawn inside the sprite: the saucer stops at row 30 and the rows below
    /// it were left empty for exactly this, so the beam costs no extra room
    /// in the badge.
    private func searchlight(_ grid: inout Sprite, frame: Int) {
        let apexX = Double(grid.width) / 2, apexY = 31
        let angle = -0.55 + Double(abs(frame) % 30) / 30 * 1.1
        for depth in 1..<(grid.height - apexY) {
            let centre = apexX + sin(angle) * Double(depth)
            let half = 1 + depth / 5
            for offset in -half...half where grid[Int(centre) + offset, apexY + depth] == nil {
                grid.plot(Int(centre) + offset,
                          apexY + depth,
                          abs(offset) == half ? .accentDim : .accentMid)
            }
        }
    }

    /// Bloop has no glass to sweep, so he does the alien thing instead: three
    /// rings rippling off his head at once, and the eyes flashing as each one
    /// launches.
    ///
    /// In the design these expanded into the space around him. He fills his
    /// own 48 cells almost edge to edge, so rings confined to empty pixels
    /// were invisible for most of their life — a ring of radius 16 is still
    /// entirely inside his head. They ripple *through* him instead: empty
    /// cells take the accent, and his own surface brightens a step as the
    /// ring crosses it. Same expanding rings, rendered in whatever they pass
    /// over, which on a filled silhouette reads better than the original did.
    private func rings(_ grid: inout Sprite, frame: Int) {
        let cx = Double(grid.width) / 2, cy = 21.0
        for index in 0..<3 {
            let radius = (Double(abs(frame)) * 1.3 + Double(index) * 8).truncatingRemainder(dividingBy: 24)
            if radius < 3 { continue }
            let tone: Slot = radius < 11 ? .accentMid : .accentDim
            var step = 0.0
            while step < 6.2832 {
                let x = Int((cx + cos(step) * radius).rounded())
                let y = Int((cy + sin(step) * radius * 0.62).rounded())
                if grid[x, y] == nil {
                    grid.plot(x, y, tone)
                } else {
                    // Never over the tell or the eyes: the mood has to stay
                    // readable through the ripple.
                    brighten(&grid, x, y, by: radius < 11 ? 2 : 1)
                }
                step += 0.05
            }
        }
        // The flash on launch. Reads as the pulse leaving him, not as a blink.
        if (Double(abs(frame)) * 1.3).truncatingRemainder(dividingBy: 24) < 3 {
            for y in 0..<grid.height {
                for x in 0..<grid.width where grid[x, y] == .accent {
                    grid.plot(x, y, .light)
                }
            }
        }
    }

    private func lightGlass(_ grid: inout Sprite, _ x: Int, _ y: Int, tone: Slot, lead: Bool) {
        switch grid[x, y] {
        case .accent where lead: grid.plot(x, y, .light)   // an eye flares
        case .visor, .visorLit:  grid.plot(x, y, tone)
        default:                 break
        }
    }

    private func brighten(_ grid: inout Sprite, _ x: Int, _ y: Int, by steps: Int) {
        let ramp: [Slot] = [.chassisDeep, .chassisShade, .chassisMid,
                            .chassisBase, .chassisLight, .chassisSpec]
        guard let slot = grid[x, y], let at = ramp.firstIndex(of: slot) else { return }
        grid.plot(x, y, ramp[min(ramp.count - 1, at + steps)])
    }

    private func repaintAccent(_ grid: inout Sprite,
                               x: Range<Int>, y: Range<Int>, with slot: Slot) {
        for j in y {
            for i in x where grid[i, j] == .accent || grid[i, j] == .accentDim {
                grid.plot(i, j, slot)
            }
        }
    }
}
