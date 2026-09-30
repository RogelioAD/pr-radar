import Foundation

extension Sprite {
    /// Scale3×: the classic pixel-art enlargement, one cell becoming nine.
    ///
    /// Not nearest-neighbour. A corner is only rounded where the two cells
    /// meeting at it agree and the ones opposite disagree, which is what turns
    /// a stepped diagonal into a diagonal instead of a bigger staircase. Used
    /// for the mood marks beside a 48-cell character and for the trophies,
    /// which were drawn at 32 and have to stand next to art drawn at 48.
    ///
    /// Deliberately not a redraw. A trophy upscaled is the same trophy; thirty
    /// hand-redrawn ones would be thirty chances for the set to stop matching.
    public func scaled3x() -> Sprite {
        var rows: [String] = []
        for y in 0..<height {
            var out = [String](repeating: "", count: 3)
            for x in 0..<width {
                let a = self[x-1, y-1], b = self[x, y-1], c = self[x+1, y-1]
                let d = self[x-1, y],   e = self[x, y],   f = self[x+1, y]
                let g = self[x-1, y+1], h = self[x, y+1], i = self[x+1, y+1]
                var n = [Slot?](repeating: e, count: 9)
                if d == b && d != h && b != f { n[0] = d }
                if (d == b && d != h && b != f && e != c) || (b == f && b != d && f != h && e != a) { n[1] = b }
                if b == f && b != d && f != h { n[2] = f }
                if (h == d && h != f && d != b && e != a) || (d == b && d != h && b != f && e != g) { n[3] = d }
                if (b == f && b != d && f != h && e != i) || (f == h && f != b && h != d && e != c) { n[5] = f }
                if h == d && h != f && d != b { n[6] = d }
                if (f == h && f != b && h != d && e != g) || (h == d && h != f && d != b && e != i) { n[7] = h }
                if f == h && f != b && h != d { n[8] = f }
                for r in 0..<3 {
                    out[r] += (0..<3).map { String(n[r * 3 + $0]?.rawValue ?? ".") }.joined()
                }
            }
            rows.append(contentsOf: out)
        }
        return Sprite(rows)
    }
}
