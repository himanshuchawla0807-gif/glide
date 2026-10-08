import AppKit
import SwiftUI

// Original native visual primitives. No bundled third-party component source.
class EffectView: NSView {
    var active = false { didSet { updateTimer() } }
    var timer: Timer?
    var time: Double = 0
    func updateTimer() {
        if active && timer == nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                guard let self else { return }; self.time += 1.0 / 30; self.needsDisplay = true
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        } else if !active { timer?.invalidate(); timer = nil }
    }
    deinit { timer?.invalidate() }
}
struct NativeMicroSlats: NSViewRepresentable {
    var active: Bool
    var theme = "Purple"
    func makeNSView(context: Context) -> SlatsView { SlatsView() }
    func updateNSView(_ view: SlatsView, context: Context) { view.active = active; view.theme = theme; view.needsDisplay = true }
}
final class SlatsView: EffectView {
    var theme = "Purple"
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard theme != "Black" else { return }
        let palette: [String:NSColor] = ["Purple": NSColor(red:0.64,green:0.43,blue:0.98,alpha:1), "Light Blue": NSColor(red:0.35,green:0.75,blue:1,alpha:1), "Deep Blue": NSColor(red:0.24,green:0.42,blue:0.95,alpha:1), "Graphite": NSColor(white:0.6,alpha:1), "Midnight": NSColor(red:0.28,green:0.3,blue:0.55,alpha:1), "Rose": NSColor(red:0.95,green:0.45,blue:0.65,alpha:1)]
        let color = palette[theme] ?? palette["Purple"]!
        for row in 0...Int(bounds.height / 12) {
            for col in 0...Int(bounds.width / 8) {
                let x = CGFloat(col * 8 + 2), y = CGFloat(row * 12 + 1)
                let brightness = (sin(Double(col) * 0.085 + Double(row) * 0.16 - time * 0.7) + 1) / 2
                color.withAlphaComponent(0.045 + brightness * 0.30).setFill()
                NSBezierPath(roundedRect:NSRect(x:x,y:y,width:3.5,height:9),xRadius:1.75,yRadius:1.75).fill()
            }
        }
    }
}
struct NativeTechText: View {
    var active: Bool
    var body: some View { Text("GLIDE").font(.system(size:27,weight:.bold,design:.rounded)).foregroundStyle(.white.opacity(0.9)) }
}
struct NativeLatticeLoader: View {
    var working: Bool
    var failed: Bool
    var body: some View {
        if working { ProgressView().controlSize(.small).frame(width:18,height:18) }
        else if failed { Image(systemName:"wifi.slash").font(.system(size:12)).foregroundStyle(.orange.opacity(0.7)) }
    }
}
