// Generates AppIcon.icns. The app has no Dock icon (LSUIElement), but the
// icon still shows on notification banners.
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

    // Rounded-square badge, blue to indigo.
    let squircle = NSBezierPath(roundedRect: rect,
                                xRadius: side * 0.225, yRadius: side * 0.225)
    NSGradient(starting: NSColor(srgbRed: 0.31, green: 0.60, blue: 0.99, alpha: 1),
               ending: NSColor(srgbRed: 0.35, green: 0.33, blue: 0.87, alpha: 1))?
        .draw(in: squircle, angle: -70)

    // White eye glyph: awaiting review.
    //
    // The colour has to come from a palette configuration — setting
    // `isTemplate` and stroking a fill colour does not tint an NSImage draw,
    // it just paints a box behind a black glyph.
    let config = NSImage.SymbolConfiguration(pointSize: side * 0.44, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)?
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
