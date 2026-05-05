import AppKit

struct IconRenderer {
    let size: CGFloat

    func render(to url: URL) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "GlanceIcon", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create icon bitmap."
            ])
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high

        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        drawBackground(in: bounds)
        drawWindowStack(in: bounds)
        drawGlanceMark(in: bounds)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "GlanceIcon", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to encode icon image."
            ])
        }

        try png.write(to: url, options: .atomic)
    }

    private func drawBackground(in bounds: NSRect) {
        let radius = size * 0.225
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.035, dy: size * 0.035), xRadius: radius, yRadius: radius)

        NSGradient(colors: [
            NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.11, alpha: 1.0),
            NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.28, alpha: 1.0),
            NSColor(calibratedRed: 0.02, green: 0.45, blue: 0.52, alpha: 1.0)
        ])?.draw(in: background, angle: 315)

        NSColor.white.withAlphaComponent(0.16).setStroke()
        background.lineWidth = size * 0.012
        background.stroke()
    }

    private func drawWindowStack(in bounds: NSRect) {
        let rects = [
            NSRect(x: size * 0.245, y: size * 0.415, width: size * 0.56, height: size * 0.34),
            NSRect(x: size * 0.195, y: size * 0.34, width: size * 0.56, height: size * 0.34),
            NSRect(x: size * 0.15, y: size * 0.265, width: size * 0.56, height: size * 0.34)
        ]

        for (index, rect) in rects.enumerated() {
            let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.045, yRadius: size * 0.045)
            let alpha = [0.95, 0.78, 0.58][index]

            NSColor(calibratedRed: 0.93, green: 0.98, blue: 1.0, alpha: alpha).setFill()
            path.fill()

            NSColor(calibratedRed: 0.0, green: 0.18, blue: 0.23, alpha: 0.24).setStroke()
            path.lineWidth = size * 0.012
            path.stroke()

            let titlebar = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.maxY - size * 0.08, width: rect.width, height: size * 0.08), xRadius: size * 0.04, yRadius: size * 0.04)
            NSColor(calibratedRed: 0.08, green: 0.52, blue: 0.58, alpha: 0.28).setFill()
            titlebar.fill()
        }
    }

    private func drawGlanceMark(in bounds: NSRect) {
        let center = NSPoint(x: size * 0.66, y: size * 0.42)
        let outer = NSBezierPath(ovalIn: NSRect(x: center.x - size * 0.13, y: center.y - size * 0.13, width: size * 0.26, height: size * 0.26))
        NSColor(calibratedRed: 0.0, green: 0.63, blue: 0.68, alpha: 1.0).setFill()
        outer.fill()

        let inner = NSBezierPath(ovalIn: NSRect(x: center.x - size * 0.052, y: center.y - size * 0.052, width: size * 0.104, height: size * 0.104))
        NSColor.white.setFill()
        inner.fill()

        let highlight = NSBezierPath(ovalIn: NSRect(x: center.x - size * 0.035, y: center.y + size * 0.035, width: size * 0.032, height: size * 0.032))
        NSColor(calibratedRed: 0.8, green: 1.0, blue: 1.0, alpha: 0.9).setFill()
        highlight.fill()
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("usage: GenerateIcon <output.png>\n", stderr)
    exit(64)
}

do {
    try IconRenderer(size: 1024).render(to: URL(fileURLWithPath: arguments[1]))
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
