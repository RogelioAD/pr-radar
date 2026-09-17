// Generates AppIcon.icns. The app has no Dock icon (LSUIElement), but the icon
// still shows on notification banners — which is why it has always mirrored the
// floating badge: the banner and the badge are the same app, and looked like
// two different ones when they disagreed.
//
// That is why this is a SwiftPM target rather than the standalone script it
// used to be. The badge is a mascot now, and a second hand-maintained copy of
// the sprite data would drift from the real one within a release. It reads the
// same `Sprite` the app draws, through a second rasteriser — AppKit rather than
// SwiftUI's Canvas — and `IconParityTests` asserts the two agree.
//
// Draws straight into an NSBitmapImageRep rather than using NSImage.lockFocus
// + tiffRepresentation, which fails in a headless context.
import AppKit
import PRRadarCore

extension NSColor {
    /// The AppKit half of the two rasterisers. Same numbers as the app's.
    convenience init(_ rgb: RGB) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
    }
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// The icon is static, so it takes the neutral face: the default character,
/// idle, with no counters — a count baked into an .icns would be a lie the
/// moment it was written.
let layout = IconArt.layout

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = false

    // Centre the art, not the slot: a perch reserves the mood-mark gutter even
    // when no mark is showing, and an icon has no layout to protect. One cell
    // of margin each side for the halo, one more for the shadow.
    guard let content = layout.contentBounds else { return nil }
    let boxWidth = content.width + 3, boxHeight = content.height + 3
    let side = CGFloat(pixels) * 0.88
    let cell = max(1, (side / CGFloat(max(boxWidth, boxHeight))).rounded(.down))
    let drawn = CGSize(width: cell * CGFloat(boxWidth), height: cell * CGFloat(boxHeight))
    // Shift so the content box lands inside the margin, then centre the whole.
    let originX = ((CGFloat(pixels) - drawn.width) / 2).rounded()
                - CGFloat(content.origin.x - 1) * cell
    let originY = ((CGFloat(pixels) - drawn.height) / 2).rounded()
                + CGFloat(content.origin.y - 1) * cell

    // Flipped: sprite rows run downward, NSGraphicsContext's y runs up.
    func fill(_ x: Int, _ y: Int, _ color: NSColor) {
        color.setFill()
        NSRect(x: originX + CGFloat(x) * cell,
               y: originY + drawn.height - CGFloat(y + 1) * cell,
               width: cell, height: cell).fill()
    }

    for point in IconArt.shadow { fill(point.x, point.y, NSColor(SpritePalette.shadow)) }
    for point in layout.halo() { fill(point.x, point.y, NSColor(SpritePalette.halo)) }
    for layer in layout.layers {
        for point in layer.sprite.litPoints {
            guard let slot = layer.sprite[point.x, point.y] else { continue }
            fill(layer.origin.x + point.x, layer.origin.y + point.y,
                 NSColor(IconArt.color(for: slot, accent: layer.accent)))
        }
    }

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// iconutil wants both @1x and @2x for each nominal size.
for size in [16, 32, 128, 256, 512] {
    guard let oneX = render(pixels: size),
          let twoX = render(pixels: size * 2)
    else {
        FileHandle.standardError.write(Data("failed to render \(size)\n".utf8))
        exit(1)
    }
    try oneX.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try twoX.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
print("iconset written to \(iconset.path)")
