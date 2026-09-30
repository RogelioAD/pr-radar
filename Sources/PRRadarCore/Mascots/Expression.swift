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

    /// Idle, and the reason the app is called what it is.
    ///
    /// A real beam turns one way and never stops, so this wraps rather than
    /// bouncing: the trail is still leaving one edge as the head re-enters the
    /// other, and there is no frame without a sweep in it.
    private func sweep(_ grid: inout Sprite, frame: Int) {
        let f = abs(frame)
        guard let glass = glassBounds else {
            // The one with no glass pulses instead: a wave climbing him, and
            // the bulbs firing when it arrives.
            let py = grid.height - (f % 26) * 54 / 26
            for r in 0..<4 {
                let y = py + r
                guard y >= 0, y < grid.height else { continue }
                for x in 0..<grid.width { brighten(&grid, x, y, by: r == 1 || r == 2 ? 2 : 1) }
            }
            if py < 7 { repaintAccent(&grid, x: 0..<grid.width, y: 0..<4, with: .accent) }
            return
        }
        // Across a wide visor, down a tall one. Same beam either way — the
        // axis is a property of the glass, not of the character.
        let wide = glass.width >= glass.height
        let span = wide ? glass.width : glass.height
        let head = (f % 18) * span / 18
        for band in stride(from: 2, through: 0, by: -1) {
            let at = ((head - band) % span + span) % span
            let lead = band == 0
            if wide {
                for y in glass.origin.y..<(glass.origin.y + glass.height) {
                    beam(&grid, glass.origin.x + at, y, lead: lead)
                }
            } else {
                for x in glass.origin.x..<(glass.origin.x + glass.width) {
                    beam(&grid, x, glass.origin.y + at, lead: lead)
                }
            }
        }
    }

    private func beam(_ grid: inout Sprite, _ x: Int, _ y: Int, lead: Bool) {
        switch grid[x, y] {
        case .accent where lead:            grid.plot(x, y, .light)   // an eye flares
        case .visor, .visorLit:             grid.plot(x, y, lead ? .accentMid : .accentDim)
        default:                            break
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
