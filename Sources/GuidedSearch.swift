import AppKit
import SwiftUI
import CoreText

final class GuidedSearchField: NSTextField {}

// The real AppKit editor retains selection, IME, undo and accessibility.
// Highlight a typed or hovered glyph without replacing the native editor.
final class GuidedFieldEditor: NSTextView {
    private var highlightedGlyph: Int?
    private var typingGeneration = 0
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let text = container ?? NSTextContainer(size: NSSize(width: 10000, height: 1000))
        storage.addLayoutManager(manager); manager.addTextContainer(text)
        super.init(frame: frameRect, textContainer: text)
        isFieldEditor = true; isRichText = false; drawsBackground = false
        isAutomaticTextReplacementEnabled = false; isAutomaticSpellingCorrectionEnabled = false
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let manager = layoutManager, let container = textContainer, !string.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = manager.glyphIndex(for: local, in: container)
        let box = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        highlightedGlyph = glyph < manager.numberOfGlyphs && box.contains(local) ? glyph : nil
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { highlightedGlyph = nil; needsDisplay = true; super.mouseExited(with: event) }
    override func didChangeText() {
        highlightedGlyph = nil
        if !hasMarkedText(), let storage = textStorage {
            storage.addAttributes([.strokeWidth: -1.0, .strokeColor: NSColor(red: 0.45, green: 0.9, blue: 0.98, alpha: 0.85)], range: NSRange(location: 0, length: storage.length))
        }
        super.didChangeText()
        typingGeneration += 1
        let generation = typingGeneration
        if let manager = layoutManager, manager.numberOfGlyphs > 0 {
            highlightedGlyph = manager.numberOfGlyphs - 1; needsDisplay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { [weak self] in
                guard let self, self.typingGeneration == generation else { return }
                self.highlightedGlyph = nil; self.needsDisplay = true
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !hasMarkedText(), selectedRange().length == 0,
              let index = highlightedGlyph, let manager = layoutManager, let container = textContainer,
              index < manager.numberOfGlyphs, let font, let context = NSGraphicsContext.current?.cgContext else { return }
        let characterIndex = manager.characterIndexForGlyph(at: index)
        let characters = Array(string.utf16)
        guard characters.indices.contains(characterIndex), characters[characterIndex] >= 33, characters[characterIndex] <= 126 else { return }
        var character = characters[characterIndex], glyph: CGGlyph = 0
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        guard CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1), let outline = CTFontCreatePathForGlyph(ctFont, glyph, nil) else { return }
        let box = manager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: container).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let line = manager.lineFragmentRect(forGlyphAt: index, effectiveRange: nil)
        let location = manager.location(forGlyphAt: index)
        context.saveGState()

        context.translateBy(x: line.minX + location.x + textContainerOrigin.x, y: line.minY + location.y + textContainerOrigin.y)
        context.scaleBy(x: 1, y: -1)
        context.addPath(outline)
        context.setStrokeColor(NSColor(red: 0.45, green: 0.9, blue: 0.98, alpha: 1).cgColor)
        context.setLineWidth(0.8); context.setLineDash(phase: 0, lengths: [2, 1.5]); context.strokePath()
        context.restoreGState()
        context.setStrokeColor(NSColor(red: 0.45, green: 0.9, blue: 0.98, alpha: 0.4).cgColor)
        context.setLineWidth(0.5); context.stroke(box.insetBy(dx: -1, dy: 1))
    }
}

struct LaunchSweep: View {
    let started: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let progress = min(1, max(0, timeline.date.timeIntervalSince(started) / 0.34))
                let eased = 1 - pow(1 - progress, 3)
                let x = -90 + (size.width + 180) * eased
                let opacity = reduceMotion ? 0 : sin(progress * .pi) * 0.8
                let glow = CGRect(x: x - 85, y: 5, width: 170, height: size.height - 10)
                context.fill(Path(roundedRect: glow, cornerRadius: 22), with: .linearGradient(
                    Gradient(colors: [.clear, Color(red: 0.69, green: 0.5, blue: 1).opacity(opacity * 0.2), .white.opacity(opacity * 0.15), .clear]),
                    startPoint: CGPoint(x: glow.minX, y: 0), endPoint: CGPoint(x: glow.maxX, y: 0)))
                for row in 0..<3 {
                    for column in 0..<8 {
                        let tail = Double(8 - column) / 8
                        let rect = CGRect(x: x - CGFloat(column * 11), y: size.height - 9 + CGFloat(row * 2), width: 5, height: 1)
                        context.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(.white.opacity(opacity * tail * (row == 1 ? 0.85 : 0.3))))
                    }
                }
            }
        }
    }
}
