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
        case .visor: glassBeam(&grid, frame: frame, down: false)
        case .hud:   glassBeam(&grid, frame: frame, down: true)
        case .beam:  searchlight(&grid, frame: frame)
        case .psi:   rings(&grid, frame: frame)
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
