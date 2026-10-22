// Renders a character to a PNG, so art can be looked at without launching
// anything.
//
//     swift run MascotPreview humanTorch /tmp/look.png
//     swift run MascotPreview humanTorch /tmp/look.png --health bad --frame 3
//     swift run MascotPreview --sheet /tmp/sheet.png
//
// `Scripts/mascot.py --png` already does this for the characters drawn in
// cells, and it can do it because it *is* the thing that draws them. The
// shelf drawn as outlines has no such script: its art lives in Swift, goes
// through the same `SpriteLayout` as everything else, and is only a picture
// once a renderer has had it. So the preview has to run the real pipeline,
// which means it has to be a target.
//
// Through AppKit rather than SwiftUI's Canvas, for the same reason MakeIcon
// is: this has to work headless, in a terminal, over ssh, with no window
// server to host a view. The two rasterisers agreeing is what IconParityTests
// is for.
//
// `Scripts/mascot.py --png` previews art it drew itself, in isolation. This
// previews what the app will actually put on screen: the real `SpriteLayout`,
// the real halo, the real ramp and tint, at the real scale. For a character
// too big to check by eye in a terminal that is the difference between
// looking at a drawing and looking at the thing being shipped.
import AppKit
import PRRadarCore

extension NSColor {
    convenience init(_ rgb: RGB) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
    }
}

let arguments = CommandLine.arguments
func flag(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: "--\(name)"), i + 1 < arguments.count else {
        return nil
    }
    return arguments[i + 1]
}

let sheet = arguments.contains("--sheet")
let health = Health(rawValue: flag("health") ?? "running") ?? .running
let frame = Int(flag("frame") ?? "0") ?? 0
let cell = CGFloat(Int(flag("cell") ?? "9") ?? 9)
/// Draw what the room and the notice draw: the head crop for a full-length
/// figure, the whole thing for a bust.
let head = arguments.contains("--head")
/// Everything that is not a flag or a flag's value.
///
/// Worked out by walking the list rather than by filtering it. Filtering on
/// what the value looks like works until a flag's value is a word — and the
/// first one that was, `--health bad`, got read as the name of a character.
let positional: [String] = {
    var out: [String] = []
    var skip = false
    for argument in arguments.dropFirst() {
        if skip { skip = false; continue }
        if argument.hasPrefix("--") {
            skip = ["health", "frame", "cell"].contains(argument.dropFirst(2))
            continue
        }
        out.append(argument)
    }
    return out
}()

/// A mood per health, so `--health` picks a face as well as a colour. The
/// badge never shows a colour without the face that goes with it, and a
/// preview that did would be a preview of something the app cannot display.
func mood(for health: Health) -> Mood {
    switch health {
    case .running:   return .idle
    case .good:      return .proud
    case .attention: return .nudging
    case .bad:       return .alarmed
    case .neutral:   return .asleep
    }
}

func draw(_ layout: SpriteLayout, in rect: NSRect, cell: CGFloat, dark: Bool) {
    // Flipped: sprite rows run downward, NSGraphicsContext's y runs up.
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: rect.minX + x * cell,
               y: rect.maxY - (y + h) * cell,
               width: w * cell, height: h * cell)
    }
    func fill(_ x: Int, _ y: Int, _ color: NSColor) {
        color.setFill()
        box(CGFloat(x), CGFloat(y), 1, 1).fill()
    }

    NSGraphicsContext.current?.shouldAntialias = false
    for point in layout.halo() { fill(point.x, point.y, NSColor(SpritePalette.halo)) }

    for layer in layout.layers {
        let tint = layer.accent.rgb
        for point in layer.sprite.litPoints {
            guard let slot = layer.sprite[point.x, point.y] else { continue }
            let rgb: RGB
            if let ramp = layer.ramp {
                rgb = SpritePalette.mascotColor(for: slot, ramp: ramp, tint: tint, dark: dark)
            } else if slot == .accent {
                rgb = tint
            } else {
                rgb = SpritePalette.color(for: slot, dark: dark)
            }
            fill(layer.origin.x + point.x, layer.origin.y + point.y, NSColor(rgb))
        }
    }
}

func render(_ cells: (width: Int, height: Int),
            _ body: (NSRect) -> Void) -> Data? {
    let pixels = (Int(CGFloat(cells.width) * cell), Int(CGFloat(cells.height) * cell))
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels.0, pixelsHigh: pixels.1,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(RGB(0.11, 0.12, 0.14)).setFill()
    NSRect(x: 0, y: 0, width: CGFloat(pixels.0), height: CGFloat(pixels.1)).fill()
    body(NSRect(x: 0, y: 0, width: CGFloat(pixels.0), height: CGFloat(pixels.1)))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let pad = 3

if sheet {
    // Every character this build ships, across every tint it can wear. The
    // thing worth checking is never how one of them looks — it is whether all
    // of them still read at every colour the app will hand them.
    let cast = Mascot.all
    let tints: [Health] = [.running, .good, .attention, .bad]
    let wide = Mascot.all.map { SpriteLayout.blockWidth(for: $0) + pad * 2 }.max() ?? 60
    let tall = Mascot.all.map { SpriteLayout.blockHeight(for: $0) + pad * 2 }.max() ?? 60
    let data = render((wide * cast.count, tall * tints.count)) { _ in
        for (column, mascot) in cast.enumerated() {
            for (row, tint) in tints.enumerated() {
                let layout = SpriteLayout.perch(mascot: mascot,
                                                style: mood(for: tint).style,
                                                frame: frame, blink: false)
                draw(layout,
                     in: NSRect(x: CGFloat(column * wide + pad) * cell,
                                y: CGFloat((tints.count - 1 - row) * tall + pad) * cell,
                                width: CGFloat(layout.width) * cell,
                                height: CGFloat(layout.height) * cell),
                     cell: cell, dark: true)
            }
        }
    }
    let out = positional.last ?? "/tmp/mascot-sheet.png"
    try data?.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
} else {
    guard positional.count >= 2,
          let id = MascotID(rawValue: positional[positional.count - 2]) else {
        print("""
            usage: MascotPreview <mascot-id> <out.png> [--health good|running|attention|bad]
                                 [--frame N] [--cell N]
                   MascotPreview --sheet <out.png>

            ids: \(MascotID.allCases.map(\.rawValue).joined(separator: ", "))
            """)
        exit(1)
    }
    let mascot = Mascot.named(id)
    let layout = SpriteLayout.perch(mascot: mascot, style: mood(for: health).style,
                                    frame: frame, blink: false,
                                    crop: head ? mascot.portraitCrop : nil)
    let data = render((layout.width + pad * 2, layout.height + pad * 2)) { rect in
        draw(layout,
             in: NSRect(x: rect.minX + CGFloat(pad) * cell,
                        y: rect.minY + CGFloat(pad) * cell,
                        width: CGFloat(layout.width) * cell,
                        height: CGFloat(layout.height) * cell),
             cell: cell, dark: true)
    }
    let out = positional[positional.count - 1]
    try data?.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
