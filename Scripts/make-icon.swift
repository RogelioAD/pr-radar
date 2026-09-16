// Generates AppIcon.icns. The app has no Dock icon (LSUIElement), but the
// icon still shows on notification banners — which is why it mirrors
// BadgeView.tile: the banner and the floating badge are the same app, and
// looked like two different ones.
//
// Draws straight into an NSBitmapImageRep rather than using NSImage.lockFocus
// + tiffRepresentation, which fails in a headless script context.
import AppKit

let sizes = [16, 32, 128, 256, 512]
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let side = CGFloat(pixels)
    let inset = side * 0.055
    let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)

    // Proportions taken from Layout: corner radius 24% of the tile, glyph 50%,
    // and the badge's 1.5pt outline on a 42pt tile.
    let radius = rect.width * 0.24
    let lineWidth = rect.width * 0.036

    // The dark-appearance variant of the tile. An .icns is one static image and
    // a banner is as likely to be light as dark, so this leans on the same
    // outline the badge uses to separate itself from whatever is behind it,
    // rather than on the ground happening to contrast.
    NSColor(white: 0, alpha: 0.92).setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

    // SwiftUI's strokeBorder draws wholly inside the shape; NSBezierPath centres
    // the stroke on the path. Inset by half the width so the outline lands in
    // the same place as the badge's, rather than half of it bleeding outside.
    let border = NSBezierPath(
        roundedRect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
        xRadius: radius - lineWidth / 2, yRadius: radius - lineWidth / 2)
    border.lineWidth = lineWidth
    NSColor(white: 1, alpha: 0.85).setStroke()
    border.stroke()

    // The same pull-request glyph the badge carries, in the same weight.
    //
    // The colour has to come from a palette configuration — setting
    // `isTemplate` and stroking a fill colour does not tint an NSImage draw,
    // it just paints a box behind a black glyph.
    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.50, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        let target = NSRect(x: (side - size.width) / 2,
                            y: (side - size.height) / 2,
                            width: size.width, height: size.height)
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// iconutil wants both @1x and @2x for each nominal size.
for size in sizes {
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
