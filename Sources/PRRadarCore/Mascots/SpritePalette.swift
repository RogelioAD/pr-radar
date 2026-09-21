import Foundation

/// A colour as plain numbers, so Core can own the palette without importing a
/// UI framework. The app turns these into `Color`; the icon generator turns the
/// same ones into `NSColor`.
public struct RGB: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(white: Double, alpha: Double = 1) {
        self.init(white, white, white, alpha: alpha)
    }
}

/// What each slot is painted, per appearance.
///
/// Here rather than in the view so there is exactly one copy: the drawer draws
/// through SwiftUI, and the icon generator draws the same sprites through
/// AppKit in a headless build step. Two rasterisers, one palette.
public enum SpritePalette {
    public static func color(for slot: Slot, dark: Bool) -> RGB {
        switch slot {
        case .outline: return dark ? RGB(white: 0.055) : RGB(white: 0.105)
        case .body:    return dark ? RGB(0.788, 0.808, 0.839) : RGB(0.875, 0.890, 0.910)
        case .shade:   return dark ? RGB(0.561, 0.592, 0.639) : RGB(0.659, 0.690, 0.733)
        case .light:   return dark ? RGB(0.969, 0.973, 0.980) : RGB(white: 1)
        case .glass:   return dark ? RGB(0.110, 0.122, 0.141) : RGB(0.165, 0.180, 0.208)
        case .blush:   return RGB(0.949, 0.635, 0.635)
        // Warmed a touch in Dark so the stack does not go muddy against the
        // drawer's material, which is far darker than a white plate expects.
        case .batter:  return dark ? RGB(0.878, 0.675, 0.365) : RGB(0.839, 0.616, 0.290)
        case .syrup:   return dark ? RGB(0.596, 0.353, 0.153) : RGB(0.545, 0.310, 0.118)

        // The metals, each a lit face and the shade under it. Lifted in Dark
        // for the same reason the batter is: the drawer's material is far
        // darker than the white plate these were mixed against, and a metal
        // that goes muddy stops being a metal.
        case .gold:        return dark ? RGB(0.937, 0.757, 0.259) : RGB(0.855, 0.655, 0.133)
        case .goldShade:   return dark ? RGB(0.706, 0.514, 0.114) : RGB(0.620, 0.439, 0.063)
        case .silver:      return dark ? RGB(0.804, 0.831, 0.878) : RGB(0.722, 0.753, 0.804)
        case .silverShade: return dark ? RGB(0.561, 0.592, 0.651) : RGB(0.502, 0.533, 0.584)
        case .bronze:      return dark ? RGB(0.843, 0.561, 0.341) : RGB(0.780, 0.490, 0.278)
        case .bronzeShade: return dark ? RGB(0.604, 0.373, 0.204) : RGB(0.549, 0.318, 0.161)

        // The motif hues. Each is the same colour the app already uses for the
        // idea it stands for where one exists — crimson and leaf sit beside
        // `Health.bad` and `Health.good` rather than arguing with them.
        case .crimson: return dark ? RGB(0.882, 0.290, 0.310) : RGB(0.800, 0.200, 0.239)
        case .azure:   return dark ? RGB(0.329, 0.580, 0.925) : RGB(0.200, 0.471, 0.851)
        case .violet:  return dark ? RGB(0.631, 0.439, 0.867) : RGB(0.529, 0.329, 0.780)
        case .leaf:    return dark ? RGB(0.329, 0.710, 0.420) : RGB(0.239, 0.620, 0.329)

        // Darker than `outline` in Dark and lighter in Light: interior line
        // work has to read *against* the fill it divides, not against the
        // desktop behind the whole drawing.
        case .ink:   return dark ? RGB(0.157, 0.169, 0.196) : RGB(0.200, 0.212, 0.239)
        case .cream: return dark ? RGB(0.949, 0.922, 0.843) : RGB(0.980, 0.953, 0.882)

        // Never drawn from here: the accent is Health.tint, resolved per layer.
        case .accent:  return RGB(white: 0.5)
        }
    }

    /// The same colour with its hue taken out — what a locked trophy is drawn
    /// in.
    ///
    /// A transform rather than a second palette, and certainly not a second set
    /// of sprites: unlocking should be the *same picture* gaining its colour,
    /// and any arrangement where the two are drawn separately is one where they
    /// can drift apart.
    ///
    /// Rec. 601 luma, because it weights green the way an eye does — an even
    /// average turns gold and azure into the same grey, which is exactly the
    /// distinction a shelf of locked trophies needs to keep.
    public static func locked(_ rgb: RGB) -> RGB {
        let luma = 0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue
        // Pulled towards mid-grey rather than used straight. At full range a
        // locked gold cup is still the brightest thing in the grid, and the
        // eye reads brightness as "lit" long before it reads colour.
        let flattened = 0.45 + (luma - 0.5) * 0.36
        return RGB(white: flattened, alpha: rgb.alpha * 0.85)
    }

    /// Fixed in both appearances on purpose. Paired with the dark outline
    /// inside it, the silhouette carries both poles of contrast — which is what
    /// lets one static treatment survive a desktop the app is not allowed to
    /// sample, without having to guess light-or-dark from `colorScheme`.
    public static let halo = RGB(0.969, 0.973, 0.980)
    public static let shadow = RGB(white: 0, alpha: 0.34)
}

extension Health {
    /// The one place colour is assigned, now as numbers so both the app and the
    /// build-time icon generator read the same scale.
    public var rgb: RGB {
        switch self {
        case .good:      return RGB(0.20, 0.70, 0.38)
        case .running:   return RGB(0.29, 0.56, 0.95)
        case .attention: return RGB(0.95, 0.62, 0.18)
        case .bad:       return RGB(0.88, 0.16, 0.13)
        case .neutral:   return RGB(white: 0.55)
        }
    }
}

/// What the app icon draws.
///
/// Static, so it takes the neutral face: the default character, idle, and no
/// counters — a count baked into an `.icns` would be a lie the moment it was
/// written.
public enum IconArt {
    public static var mascot: Mascot { .named(MascotID.allCases[0]) }

    public static var layout: SpriteLayout {
        .perch(mascot: mascot, style: Mood.idle.style, frame: 0, blink: false)
    }

    /// Cells the drop shadow covers: the silhouette offset by one, minus
    /// anything the art already occupies.
    public static var shadow: [Point] {
        let art = layout
        return art.layers.flatMap { layer in
            layer.sprite.litPoints.compactMap { point in
                let shifted = Point(layer.origin.x + point.x + 1, layer.origin.y + point.y + 1)
                return art.isLit(x: shifted.x, y: shifted.y) ? nil : shifted
            }
        }
    }

    /// The icon is one static image and a banner is as likely to be light as
    /// dark, so it commits to the dark-appearance palette and leans on the halo
    /// for separation — the same bargain the old tile made with its outline.
    public static func color(for slot: Slot, accent: Health) -> RGB {
        slot == .accent ? accent.rgb : SpritePalette.color(for: slot, dark: true)
    }
}
