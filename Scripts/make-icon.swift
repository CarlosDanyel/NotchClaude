import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: CGFloat) -> Data? {
    let pixels = Int(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = size / 1024
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = canvas.insetBy(dx: 100 * scale, dy: 100 * scale)
    let squircle = NSBezierPath(roundedRect: inset, xRadius: 185 * scale, yRadius: 185 * scale)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.set()
    NSGradient(colors: [NSColor(white: 0.17, alpha: 1), NSColor(white: 0.05, alpha: 1)])?.draw(in: squircle, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    squircle.addClip()
    let notchWidth = 360 * scale
    let notchHeight = 92 * scale
    let notchRect = NSRect(x: canvas.midX - notchWidth / 2, y: inset.maxY - notchHeight, width: notchWidth, height: notchHeight + 40 * scale)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: notchRect, xRadius: 46 * scale, yRadius: 46 * scale).fill()

    let orange = NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1)
    let dot = NSRect(x: canvas.midX - 112 * scale, y: inset.maxY - 64 * scale, width: 30 * scale, height: 30 * scale)
    orange.setFill()
    NSBezierPath(ovalIn: dot).fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let glyph = NSAttributedString(string: "✻", attributes: [
        .font: NSFont.systemFont(ofSize: 470 * scale, weight: .black),
        .foregroundColor: orange,
        .paragraphStyle: paragraph
    ])
    let glyphSize = glyph.size()
    glyph.draw(in: NSRect(x: canvas.midX - glyphSize.width / 2, y: canvas.midY - glyphSize.height / 2 - 40 * scale, width: glyphSize.width, height: glyphSize.height))

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, size) in sizes {
    if let data = render(size: size) {
        try data.write(to: output.appendingPathComponent("\(name).png"))
    }
}
