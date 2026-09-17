import Foundation

/// A cell in a sprite grid. One character per pixel in the source literals,
/// so a whole character is sixteen readable strings rather than a blob.
public enum Slot: Character, CaseIterable, Sendable {
    case outline = "k"
    case body    = "g"
    case shade   = "d"
    case light   = "w"
    case glass   = "v"
    case blush   = "p"
    /// The only slot that takes a live colour. Everything else is fixed by the
    /// appearance; this one is `Health.tint`, which is what keeps a mascot and
    /// the count it sits next to from ever disagreeing.
    case accent  = "a"
    /// Portrait slots. The six above are a greyscale set with one pink, which
    /// is all a drawn character needs; a photographed one needs skin, and skin
    /// quantised into grey is a smudge rather than a face. Only the portrait
    /// uses these, so the drawn characters are untouched by their existence.
    case skinLit   = "l"
    case skin      = "s"
    case skinShade = "n"
    case tan       = "t"
}

public struct Point: Hashable, Sendable {
    public let x: Int
    public let y: Int
    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

/// A rectangular grid of slots, parsed once from string literals.
///
/// Indexing is by `Int`, not `String.Index`: the grid is read pixel by pixel on
/// every frame, and walking a `String` for each one is the kind of cost that
/// only shows up as a warm laptop.
public struct Sprite: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Row-major, `nil` where the source had `.`.
    public private(set) var cells: [Slot?]

    /// Traps on malformed art rather than drawing it wrong. A sprite literal is
    /// source code, so a bad one is a compile-time mistake noticed at first run
    /// — and every literal in the app is built by the test suite.
    public init(_ rows: [String]) {
        precondition(!rows.isEmpty, "sprite has no rows")
        let w = rows[0].count
        precondition(rows.allSatisfy { $0.count == w },
                     "sprite rows disagree on width: \(rows.map(\.count))")
        width = w
        height = rows.count
        cells = rows.flatMap { row in
            row.map { character -> Slot? in
                if character == "." { return nil }
                guard let slot = Slot(rawValue: character) else {
                    preconditionFailure("unknown sprite slot '\(character)'")
                }
                return slot
            }
        }
    }

    /// Out of bounds reads as empty, so callers can probe neighbours without
    /// guarding every edge.
    public subscript(x: Int, y: Int) -> Slot? {
        get {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            return cells[y * width + x]
        }
        set {
            precondition(x >= 0 && y >= 0 && x < width && y < height,
                         "write out of bounds at (\(x), \(y))")
            cells[y * width + x] = newValue
        }
    }

    public var litPoints: [Point] {
        (0..<height).flatMap { y in
            (0..<width).compactMap { x in self[x, y] == nil ? nil : Point(x, y) }
        }
    }

    /// The sticker halo: every empty cell touching a lit one, including the
    /// ring just outside the grid. Drawn in a fixed near-white outside the dark
    /// outline, which is what lets one static treatment survive a desktop the
    /// app is not allowed to look at.
    public func halo() -> Set<Point> {
        var result: Set<Point> = []
        for y in -1...height {
            for x in -1...width where self[x, y] == nil {
                let touches = (-1...1).contains { dy in
                    (-1...1).contains { dx in self[x + dx, y + dy] != nil }
                }
                if touches { result.insert(Point(x, y)) }
            }
        }
        return result
    }
}
