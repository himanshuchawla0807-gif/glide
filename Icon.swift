import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = NSRect(x: 64, y: 64, width: 896, height: 896)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 205, yRadius: 205)
        NSColor(red: 0.10, green: 0.065, blue: 0.20, alpha: 1).setFill(); shape.fill()
        NSGradient(starting: NSColor(red: 0.30, green: 0.18, blue: 0.49, alpha: 1), ending: NSColor(red: 0.075, green: 0.04, blue: 0.15, alpha: 1))!.draw(in: shape, angle: -60)
        NSColor.white.withAlphaComponent(0.15).setStroke(); shape.lineWidth = 3; shape.stroke()
        for col in 0..<19 {
            for row in 0..<15 {
                let slat = NSBezierPath(roundedRect: NSRect(x: 135 + col * 40, y: 150 + row * 49, width: 12, height: 27), xRadius: 6, yRadius: 6)
                NSColor(red: 0.75, green: 0.55, blue: 1, alpha: 0.08 + 0.14 * (sin(Double(col + row) * 0.45) + 1) / 2).setFill(); slat.fill()
            }
        }
        let glass = NSBezierPath(roundedRect: NSRect(x: 212, y: 212, width: 600, height: 600), xRadius: 170, yRadius: 170)
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0.035), NSColor(red: 0.75, green: 0.58, blue: 1, alpha: 0.20)])!.draw(in: glass, angle: -55)
        NSColor.white.withAlphaComponent(0.38).setStroke(); glass.lineWidth = 3; glass.stroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 300, y: 310)); path.curve(to: NSPoint(x: 706, y: 718), controlPoint1: NSPoint(x: 330, y: 560), controlPoint2: NSPoint(x: 468, y: 680))
        path.move(to: NSPoint(x: 464, y: 714)); path.line(to: NSPoint(x: 716, y: 714)); path.line(to: NSPoint(x: 716, y: 464))
        path.lineWidth = 65; path.lineCapStyle = .round; path.lineJoinStyle = .round
        NSColor(red: 0.84, green: 0.72, blue: 1, alpha: 1).setStroke(); path.stroke()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
