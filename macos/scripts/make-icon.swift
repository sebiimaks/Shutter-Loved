import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let canvas = NSSize(width: pixels, height: pixels)
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: Double(pixels) * 0.08, y: Double(pixels) * 0.08, width: Double(pixels) * 0.84, height: Double(pixels) * 0.84), xRadius: Double(pixels) * 0.18, yRadius: Double(pixels) * 0.18).fill()
        let config = NSImage.SymbolConfiguration(pointSize: Double(pixels) * 0.58, weight: .light)
        if let symbol = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: nil)?.withSymbolConfiguration(config)?.withSymbolConfiguration(.init(paletteColors: [.white])) {
            symbol.draw(in: NSRect(x: Double(pixels) * 0.22, y: Double(pixels) * 0.22, width: Double(pixels) * 0.56, height: Double(pixels) * 0.56))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
