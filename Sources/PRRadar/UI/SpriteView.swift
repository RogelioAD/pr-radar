import SwiftUI
import PRRadarCore

extension Color {
    /// Core owns the palette as plain numbers so the headless icon generator
    /// can read the same ones; this is the only place they become a `Color`.
    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue,
                  opacity: rgb.alpha)
    }
}

/// Draws a `SpriteLayout` at an integer cell size.
///
/// Everything about where the pixels go was decided in `PRRadarCore`; this only
/// turns slots into colours and fills rectangles. The one rule it owns is that
/// the cell size stays whole — a fractional one is what turns pixel art into a
/// blurry JPEG.
struct SpriteCanvas: View {
    let layout: SpriteLayout
    let scale: CGFloat
    var halo = false
    var shadow = false
    /// Draws the same art with its colour taken out.
    ///
    /// A flag rather than a second set of sprites, because a locked trophy and
    /// an unlocked one have to be *the same picture* — anything that draws
    /// them separately is an arrangement in which they can drift apart, and
    /// the whole moment the room is built around is one gaining its colour.
    var locked = false

    @Environment(\.colorScheme) private var colorScheme

    private static let haloColor = Color(SpritePalette.halo)

    private var leadingPad: Int { halo ? 1 : 0 }
    private var trailingPad: Int { (halo ? 1 : 0) + (shadow ? 1 : 0) }

    private var cells: (width: Int, height: Int) {
        (layout.width + leadingPad + trailingPad,
         layout.height + leadingPad + trailingPad)
    }

    var body: some View {
        let grid = cells
        Canvas(rendersAsynchronously: false) { context, _ in
            let origin = CGFloat(leadingPad)
            func fill(_ x: Int, _ y: Int, _ color: Color) {
                context.fill(
                    Path(CGRect(x: (CGFloat(x) + origin) * scale,
                                y: (CGFloat(y) + origin) * scale,
                                width: scale, height: scale)),
                    with: .color(color))
            }

            if shadow {
                for layer in layout.layers {
                    for point in layer.sprite.litPoints {
                        let x = layer.origin.x + point.x + 1
                        let y = layer.origin.y + point.y + 1
                        if layout.isLit(x: x, y: y) { continue }
                        fill(x, y, Color(SpritePalette.shadow))
                    }
                }
            }
            if halo {
                for point in layout.halo() { fill(point.x, point.y, Self.haloColor) }
            }
            for layer in layout.layers {
                let accent = locked
                    ? Color(SpritePalette.locked(layer.accent.rgb))
                    : layer.accent.tint
                for point in layer.sprite.litPoints {
                    guard let slot = layer.sprite[point.x, point.y] else { continue }
                    fill(layer.origin.x + point.x, layer.origin.y + point.y,
                         slot == .accent ? accent : color(for: slot))
                }
            }
        }
        .frame(width: CGFloat(grid.width) * scale,
               height: CGFloat(grid.height) * scale)
    }

    private func color(for slot: Slot) -> Color {
        let rgb = SpritePalette.color(for: slot, dark: colorScheme == .dark)
        return Color(locked ? SpritePalette.locked(rgb) : rgb)
    }
}

/// A character with a mood, animated or held still.
///
/// `animated` is a decision the caller makes, not one this view guesses. The
/// drawer can afford a timeline because it stops existing when the drawer
/// collapses; the badge is on screen all day and holds frame zero unless
/// something is actually happening.
struct MascotView: View {
    let mascot: Mascot
    let style: SpriteStyle
    let scale: CGFloat
    var crop: Int?
    /// Set to draw the whole floating widget — character, mark and counters.
    var counters: Counters?
    var tempo: Tempo = .lively
    var halo = false
    var shadow = false

    struct Counters {
        let reviews: Int
        let reviewHealth: Health
        let readyToMerge: Int
    }

    /// How often the character is redrawn — a decision the caller makes, not
    /// one this view guesses, because the two surfaces can afford very
    /// different things.
    ///
    /// Measured on a release build, badge only, over 25 seconds at rest:
    ///
    ///     still     0.04% of one core
    ///     resting   0.44%
    ///     lively    3.20%
    ///
    /// Which is why the badge idles at `resting` rather than `lively`: seven
    /// times cheaper, and the difference between a character that breathes and
    /// one that is animating at you all day. `still` is a further ten times
    /// cheaper again, but it buys a mascot that looks switched off.
    enum Tempo {
        /// Six frames a second. What the drawer runs at, and what the badge
        /// switches to while something is actually happening to it. The drawer
        /// can afford it unconditionally: it stops existing when it collapses.
        case lively
        /// Two. The badge is on screen all day, so at rest it breathes rather
        /// than animates. A third of the redraws, and the bob and the Zzz
        /// stretch into something that reads as idling instead of looping —
        /// `asleep` takes three seconds to rise and fall rather than one.
        case resting
        /// No timeline at all. Reduce Motion, and anywhere a timer would be
        /// scheduled for a character nobody is looking at.
        case still

        var fps: Double {
            switch self {
            case .lively: return 6
            case .resting: return 2
            case .still: return 0
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if tempo == .still || reduceMotion {
            canvas(frame: 0, blink: false)
        } else {
            let fps = tempo.fps
            TimelineView(.periodic(from: .now, by: 1 / fps)) { timeline in
                let frame = Int(timeline.date.timeIntervalSinceReferenceDate * fps)
                canvas(frame: frame, blink: Blink.isBlinking(frame: frame, fps: fps))
            }
        }
    }

    private func canvas(frame: Int, blink: Bool) -> some View {
        // Only an open-eyed mood blinks; shutting an already-shut eye is a
        // frame where nothing happens, which reads as a stutter.
        let blinking = blink && style.eyes == .open
        let layout: SpriteLayout = {
            if let counters {
                return .widget(mascot: mascot, style: style, frame: frame, blink: blinking,
                               reviews: counters.reviews,
                               reviewHealth: counters.reviewHealth,
                               readyToMerge: counters.readyToMerge)
            }
            return .perch(mascot: mascot, style: style, frame: frame,
                          blink: blinking, crop: crop)
        }()
        return SpriteCanvas(layout: layout, scale: scale, halo: halo, shadow: shadow)
    }
}
