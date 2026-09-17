import Foundation

/// A whole composition — character, mood mark, counter chips — resolved into
/// placed layers plus one shared halo.
///
/// All of it lives here rather than in the view so the arithmetic is testable,
/// and because the placement rules are exactly the kind that look right in a
/// mockup and land three pixels off in a build.
public struct SpriteLayout: Sendable {
    public struct Layer: Sendable {
        public let sprite: Sprite
        public let origin: Point
        /// What this layer's `.accent` cells resolve to.
        public let accent: Health
    }

    public let layers: [Layer]
    public let width: Int
    public let height: Int

    // Geometry shared by every composition.
    public static let characterSize = 16
    /// The mark sits in a gutter to the character's right.
    public static let markOrigin = 16
    public static let blockWidth = markOrigin + Mark.width
    /// Gap between the character's feet and the chip row.
    public static let chipGap = 2

    public func isLit(x: Int, y: Int) -> Bool {
        layers.contains { $0.sprite[x - $0.origin.x, y - $0.origin.y] != nil }
    }

    /// The tight box around everything actually drawn.
    ///
    /// `width`/`height` are deliberately *not* this: a perch reserves the mark
    /// gutter whether or not a mark is showing, so the header does not reflow
    /// every time one blinks out. Anything that needs to centre the art rather
    /// than the slot — the app icon, which has no layout to protect — wants
    /// this instead.
    public var contentBounds: (origin: Point, width: Int, height: Int)? {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for layer in layers {
            for point in layer.sprite.litPoints {
                let x = layer.origin.x + point.x, y = layer.origin.y + point.y
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return (Point(minX, minY), maxX - minX + 1, maxY - minY + 1)
    }

    /// One halo around the union of every layer, so the composition reads as a
    /// single sticker rather than three stuck together.
    public func halo() -> Set<Point> {
        var result: Set<Point> = []
        for y in -1...height {
            for x in -1...width where !isLit(x: x, y: y) {
                let touches = (-1...1).contains { dy in
                    (-1...1).contains { dx in isLit(x: x + dx, y: y + dy) }
                }
                if touches { result.insert(Point(x, y)) }
            }
        }
        return result
    }
}

extension SpriteLayout {
    /// Character plus mood mark. What the drawer shows.
    ///
    /// `crop` trims the bust's collar for small perches.
    public static func perch(mascot: Mascot,
                             style: SpriteStyle,
                             frame: Int,
                             blink: Bool,
                             crop: Int? = nil) -> SpriteLayout {
        let rows = min(crop ?? mascot.sprite.height, mascot.sprite.height)
        let bob = min(2, style.offset(frame: frame) * mascot.bobScale)
        let character = cropped(mascot.frame(eyes: blink ? .shut : style.eyes), rows: rows)

        var layers = [Layer(sprite: character, origin: Point(0, bob), accent: style.health)]
        let mark = style.mark(frame: frame)
        if mark != .none {
            layers.append(Layer(sprite: mark.sprite,
                                origin: Point(markOrigin, bob), accent: style.health))
        }
        return SpriteLayout(layers: layers,
                            width: blockWidth,
                            height: rows + maxBobRoom)
    }

    /// The whole floating widget: character, mark, and a chip per non-zero
    /// count beneath.
    ///
    /// Chips centre on the **character's** sixteen columns, not on the 21-wide
    /// block — that block carries the mark gutter on its right, and centring
    /// against it pushes the chips off to the same side.
    public static func widget(mascot: Mascot,
                              style: SpriteStyle,
                              frame: Int,
                              blink: Bool,
                              reviews: Int,
                              reviewHealth: Health,
                              readyToMerge: Int) -> SpriteLayout {
        var chips: [(sprite: Sprite, accent: Health)] = []
        if reviews > 0 {
            chips.append((Counter.chip(Counter.text(for: reviews)), reviewHealth))
        }
        if readyToMerge > 0 {
            chips.append((Counter.chip(Counter.text(for: readyToMerge)), .good))
        }

        let chipsWidth = chips.isEmpty
            ? 0
            : chips.reduce(0) { $0 + $1.sprite.width } + (chips.count - 1)

        let centre = characterSize / 2
        // A wide chip row can reach further left than the character does; the
        // whole composition shifts right by that much rather than clipping.
        let leftOverhang = max(0, Int((Double(chipsWidth) / 2).rounded(.up)) - centre)
        let rightExtent = max(blockWidth, centre + chipsWidth / 2)
        let characterX = leftOverhang

        let bob = min(2, style.offset(frame: frame) * mascot.bobScale)
        var layers = [Layer(sprite: mascot.frame(eyes: blink ? .shut : style.eyes),
                            origin: Point(characterX, bob), accent: style.health)]
        let mark = style.mark(frame: frame)
        if mark != .none {
            layers.append(Layer(sprite: mark.sprite,
                                origin: Point(characterX + markOrigin, bob),
                                accent: style.health))
        }

        var x = characterX + centre - chipsWidth / 2
        let chipY = characterSize + maxBobRoom + chipGap
        for chip in chips {
            layers.append(Layer(sprite: chip.sprite, origin: Point(x, chipY),
                                accent: chip.accent))
            x += chip.sprite.width + 1
        }

        return SpriteLayout(
            layers: layers,
            width: leftOverhang + rightExtent,
            height: chipY + (chips.isEmpty ? 0 : Counter.height))
    }

    /// Room kept below a sprite so a bobbing character is never clipped.
    static let maxBobRoom = 2

    private static func cropped(_ sprite: Sprite, rows: Int) -> Sprite {
        guard rows < sprite.height else { return sprite }
        var trimmed: [String] = []
        for y in 0..<rows {
            trimmed.append(String((0..<sprite.width).map { x in
                sprite[x, y]?.rawValue ?? "."
            }))
        }
        return Sprite(trimmed)
    }
}
