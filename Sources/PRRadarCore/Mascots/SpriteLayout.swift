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
        /// The character's chassis ramp, for layers that are a character.
        /// nil on marks, chips and pancakes, which are drawn from the shared
        /// palette and the accent alone.
        public let ramp: ChassisRamp?

        public init(sprite: Sprite, origin: Point, accent: Health,
                    ramp: ChassisRamp? = nil) {
            self.sprite = sprite
            self.origin = origin
            self.accent = accent
            self.ramp = ramp
        }
    }

    public let layers: [Layer]
    public let width: Int
    public let height: Int

    // Geometry shared by every composition.
    //
    // Derived from the art rather than fixed. The cast was 16 cells and is now
    // 48, and a constant here is a constant that has to be found and changed
    // in step with every drawing — the kind of pair that silently drifts. One
    // unit is a sixteenth of the character's width, so the furniture around it
    // keeps its old proportions whatever the cast is drawn at.
    public static func unit(for mascot: Mascot) -> Int {
        max(1, mascot.sprite.width / 16)
    }
    /// Gap between the character's feet and the chip row, in units.
    public static let chipGapUnits = 2
    /// Room kept below a sprite so a bobbing character is never clipped.
    static let maxBobUnits = 2

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
        let unit = unit(for: mascot)
        let art = mascot.art(powered: style.powered)
        let rows = min(crop ?? art.height, art.height)
        let bob = min(2, style.offset(frame: frame) * mascot.bobScale) * unit
        // Cropping takes columns as well as rows when the character says
        // where its head is. A full-length figure cropped to rows alone
        // keeps two shoulders' worth of empty air either side of the head,
        // and that air is then scaled to fit a 26-point slot.
        let columns = rows < art.height ? mascot.headBox : nil
        let character = cropped(mascot.frame(eyes: blink ? .shut : style.eyes,
                                             frame: frame,
                                             sweeping: style.sweeps,
                                             breath: style.breath,
                                             powered: style.powered),
                                rows: rows, columns: columns)

        var layers = [Layer(sprite: character, origin: Point(0, bob),
                            accent: style.health,
                            ramp: mascot.ramp(powered: style.powered))]
        // Fire that runs off the bottom of the art, as its own layer rather
        // than clipped to the character's own rows. Only drawn as far as
        // the crop reaches: a cropped perch is already saying it does not
        // want the lower half of him.
        if rows >= art.height,
           let spill = mascot.flameOverflow(frame: frame, breath: style.breath) {
            layers.append(Layer(sprite: spill,
                                origin: Point(0, bob + art.height),
                                accent: style.health,
                                ramp: mascot.ramp(powered: style.powered)))
        }
        let mark = style.mark(frame: frame)
        if mark != .none {
            layers.append(Layer(sprite: furniture(mark.sprite, unit: unit),
                                origin: Point(character.width + unit, bob),
                                accent: style.health, ramp: nil))
        }
        let spillRoom = rows >= art.height ? mascot.overflowRows : 0
        return SpriteLayout(layers: layers,
                            width: character.width + unit + Mark.width * unit,
                            height: rows + spillRoom + maxBobUnits * unit)
    }

    /// The character's rows plus the room kept under a bobbing one.
    public static func blockHeight(for mascot: Mascot) -> Int {
        mascot.sprite.height + mascot.overflowRows + maxBobUnits * unit(for: mascot)
    }

    /// The character's own columns plus the mark gutter beside them.
    public static func blockWidth(for mascot: Mascot) -> Int {
        let unit = unit(for: mascot)
        return mascot.sprite.width + unit + Mark.width * unit
    }

    /// Marks and counter chips are authored at the old scale and enlarged to
    /// match the character, rather than redrawn — `scaled3x` rounds a glyph's
    /// corners on the way up, so an enlarged exclamation mark is still the
    /// same exclamation mark.
    private static func furniture(_ sprite: Sprite, unit: Int) -> Sprite {
        switch unit {
        case 3: return sprite.scaled3x()
        // Six, for the cast drawn at 96 cells. Three then two rather than a
        // flat six: `scaled3x` is the pass that turns a stepped diagonal
        // into a diagonal, and it only has anything to work with on the
        // original art. Run on its own output it would round the corners a
        // second time and soften the glyph into a blob.
        case 6: return sprite.scaled3x().scaled2x()
        default: return sprite
        }
    }

    /// The whole floating widget: character, mark, and a chip per non-zero
    /// count beneath.
    ///
    /// Chips centre on the **character's** own columns, not on the whole
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

        let unit = unit(for: mascot)
        chips = chips.map { (furniture($0.sprite, unit: unit), $0.accent) }
        let chipsWidth = chips.isEmpty
            ? 0
            : chips.reduce(0) { $0 + $1.sprite.width } + (chips.count - 1) * unit

        let art = mascot.art(powered: style.powered)
        let centre = art.width / 2
        // A wide chip row can reach further left than the character does; the
        // whole composition shifts right by that much rather than clipping.
        let leftOverhang = max(0, Int((Double(chipsWidth) / 2).rounded(.up)) - centre)
        let rightExtent = max(blockWidth(for: mascot), centre + chipsWidth / 2)
        let characterX = leftOverhang

        let bob = min(2, style.offset(frame: frame) * mascot.bobScale) * unit
        var layers = [Layer(sprite: mascot.frame(eyes: blink ? .shut : style.eyes,
                                                 frame: frame,
                                                 sweeping: style.sweeps,
                                                 breath: style.breath,
                                                 powered: style.powered),
                            origin: Point(characterX, bob),
                            accent: style.health,
                            ramp: mascot.ramp(powered: style.powered))]
        if let spill = mascot.flameOverflow(frame: frame, breath: style.breath) {
            layers.append(Layer(sprite: spill,
                                origin: Point(characterX, bob + art.height),
                                accent: style.health,
                                ramp: mascot.ramp(powered: style.powered)))
        }
        let mark = style.mark(frame: frame)
        if mark != .none {
            layers.append(Layer(sprite: furniture(mark.sprite, unit: unit),
                                origin: Point(characterX + art.width + unit, bob),
                                accent: style.health, ramp: nil))
        }

        var x = characterX + centre - chipsWidth / 2
        // Below the reserved flame room, not just below the art, or a blast
        // lands on top of the counts.
        let chipY = art.height + mascot.overflowRows
                  + (maxBobUnits + chipGapUnits) * unit
        for chip in chips {
            layers.append(Layer(sprite: chip.sprite, origin: Point(x, chipY),
                                accent: chip.accent, ramp: nil))
            x += chip.sprite.width + unit
        }

        return SpriteLayout(
            layers: layers,
            width: leftOverhang + rightExtent,
            height: chipY + (chips.isEmpty ? 0 : Counter.height * unit))
    }

    private static func cropped(_ sprite: Sprite, rows: Int,
                                columns: Mascot.HeadBox? = nil) -> Sprite {
        let xs = columns.map { $0.x..<min(sprite.width, $0.x + $0.width) }
               ?? 0..<sprite.width
        guard rows < sprite.height || xs.count < sprite.width else { return sprite }
        var trimmed: [String] = []
        for y in 0..<min(rows, sprite.height) {
            trimmed.append(String(xs.map { x in sprite[x, y]?.rawValue ?? "." }))
        }
        return Sprite(trimmed)
    }
}
