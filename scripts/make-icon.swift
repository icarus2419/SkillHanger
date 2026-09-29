import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
guard let logo = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
    fatalError("Missing SkillHanger logo asset")
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let edge = CGFloat(pixels)
        let rect = NSRect(x: edge * 0.06, y: edge * 0.06, width: edge * 0.88, height: edge * 0.88)
        let body = NSBezierPath(roundedRect: rect, xRadius: edge * 0.20, yRadius: edge * 0.20)
        NSGradient(starting: NSColor(calibratedRed: 0.080, green: 0.065, blue: 0.075, alpha: 1),
                   ending: NSColor(calibratedRed: 0.17, green: 0.09, blue: 0.115, alpha: 1))!.draw(in: body, angle: 90)
        NSColor(white: 1, alpha: 0.09).setStroke()
        body.lineWidth = max(0.5, edge * 0.002)
        body.stroke()
        NSGraphicsContext.current?.imageInterpolation = .high
        logo.draw(in: NSRect(x: edge * 0.14, y: edge * 0.14, width: edge * 0.72, height: edge * 0.72))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
