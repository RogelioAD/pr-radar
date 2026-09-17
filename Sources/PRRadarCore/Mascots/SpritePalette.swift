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
        // Never drawn from here: the accent is Health.tint, resolved per layer.
        case .accent:  return RGB(white: 0.5)
        }
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
