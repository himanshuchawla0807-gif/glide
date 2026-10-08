import SwiftUI
import AppKit
import QuartzCore

struct CircularStrands: NSViewRepresentable {
    let active: Bool
    func makeNSView(context: Context) -> PublicOrbView { PublicOrbView() }
    func updateNSView(_ view: PublicOrbView, context: Context) { view.setActive(active) }
}
// Original compositor-only orb: rotating translucent gradients inside a spherical mask.
final class PublicOrbView: NSView {
    private let sphere = CALayer()
    private var ribbons: [CAGradientLayer] = []
    override init(frame: NSRect) {
        super.init(frame:frame); wantsLayer = true
        sphere.masksToBounds = true
        sphere.backgroundColor = NSColor(red:0.06,green:0.035,blue:0.12,alpha:0.3).cgColor
        layer?.addSublayer(sphere)
        for i in 0..<3 {
            let ribbon = CAGradientLayer()
            let color = [NSColor.systemPink, NSColor.systemCyan, NSColor.systemPurple][i]
            ribbon.colors = [NSColor.clear.cgColor,color.withAlphaComponent(0.85).cgColor,NSColor.white.withAlphaComponent(0.85).cgColor,NSColor.clear.cgColor]
            ribbon.locations = [0,0.35,0.5,1]; ribbon.startPoint = CGPoint(x:0,y:0); ribbon.endPoint = CGPoint(x:1,y:1)
            sphere.addSublayer(ribbon); ribbons.append(ribbon)
        }
    }
    required init?(coder:NSCoder) { fatalError() }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true)
        sphere.frame = bounds.insetBy(dx:5,dy:5); sphere.cornerRadius = sphere.bounds.width / 2
        for (i,ribbon) in ribbons.enumerated() { ribbon.bounds = CGRect(x:0,y:0,width:sphere.bounds.width*1.3,height:sphere.bounds.height*0.55); ribbon.position = CGPoint(x:sphere.bounds.midX,y:sphere.bounds.midY); ribbon.cornerRadius = 12; ribbon.transform = CATransform3DMakeRotation(CGFloat(i)*2.1,0,0,1) }
        CATransaction.commit()
    }
    func setActive(_ active:Bool) {
        for (i,ribbon) in ribbons.enumerated() {
            if !active || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { ribbon.removeAllAnimations(); continue }
            guard ribbon.animation(forKey:"flow") == nil else { continue }
            let animation = CABasicAnimation(keyPath:"transform.rotation.z")
            animation.fromValue = Double(i)*2.1; animation.toValue = Double(i)*2.1 + .pi*2
            animation.duration = Double(8+i*3); animation.repeatCount = .infinity
            ribbon.add(animation,forKey:"flow")
        }
    }
}
