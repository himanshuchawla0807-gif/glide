import AppKit
import SwiftUI
import Carbon
import OSLog
import QuartzCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = SearchModel()
    var panel: FloatingPanel!
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem!
    var hotkey: EventHotKeyRef?
    var handler: EventHandlerRef?
    var localMonitor: Any?
    var globalMonitor: Any?
    let guidedEditor = GuidedFieldEditor(frame: .zero, textContainer: nil)
    var departure = false
    var panelTop: CGFloat = 0
    var requestedHeight: CGFloat = 136
    var previousApp: NSRunningApplication?
    let logger = Logger(subsystem: "com.himanshu.glide", category: "Lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Keep the single resident copy responsible for the global shortcut.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.himanshu.glide").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first { existing.activate(); NSApp.terminate(nil); return }
        createPanel(); createMenu(); registerHotkey()
        model.layoutChanged = { [weak self] in self?.resizePanel() }
        model.startBridge()
        model.didOpen = { [weak self] in self?.animateDeparture() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, self.panel.isVisible {
                if event.keyCode == UInt16(kVK_Escape) { self.hide(); return nil }
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," { self.showSettings(); return nil }
            }
            if event.type != .keyDown, self.panel.isVisible, event.window != self.panel { self.hide(restoreFocus: false) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(restoreFocus: false) }
        }
        if model.bridge.paired { show() } else { showSettings() }
    }
    func createPanel() {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 136), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Glide Search"
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true; panel.isMovableByWindowBackground = false; panel.isReleasedWhenClosed = false
        panel.delegate = self
        let material = NSView(frame: panel.contentView!.bounds)
        material.wantsLayer = true; material.layer?.cornerRadius = 42; material.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: SearchPanelView(model: model, settings: { [weak self] in self?.showSettings() }, dismiss: { [weak self] in self?.hide() }))
        hosting.frame = material.bounds; hosting.autoresizingMask = [.width, .height]
        material.addSubview(hosting); panel.contentView = material
    }
    func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.up.right.circle", accessibilityDescription: "Glide")
        let menu = NSMenu()
        let search = NSMenuItem(title: "Search with Glide     ⇧ Space", action: #selector(toggle), keyEquivalent: "")
        search.target = self; menu.addItem(search)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Glide", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit); statusItem.menu = menu
    }
    func registerHotkey() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.logger.notice("Global Shift Space received"); delegate.toggle() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: 0x474C4944, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(shiftKey), id, GetApplicationEventTarget(), 0, &hotkey)
        model.hotkeyAvailable = result == noErr
        logger.notice("Hotkey registration status: \(result)")
        if result != noErr { model.error = "Shift + Space is already in use. Glide is available from the menu bar." }
    }
    @objc func toggle() { if panel.isVisible { hide() } else { show() } }
    func show() {
        logger.notice("Search panel shown")
        departure = false; panel.alphaValue = 1
        previousApp = NSWorkspace.shared.frontmostApplication
        model.reset()
        if !model.hotkeyAvailable { model.error = "Shift + Space is unavailable. Check other shortcut apps." }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.midX - 290, y: area.minY + area.height * 0.70 - model.panelHeight))
        panelTop = panel.frame.maxY
        requestedHeight = -1
        resizePanel(); model.panelVisible = true
        panel.orderFrontRegardless(); panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            func findInput(_ view: NSView) -> NSTextField? {
                if let field = view as? NSTextField { return field }
                return view.subviews.lazy.compactMap { findInput($0) }.first
            }
            if let root = self.panel.contentView, let input = findInput(root) {
                self.panel.makeFirstResponder(input)
                if let editor = input.currentEditor() as? NSTextView {
                    editor.isAutomaticTextReplacementEnabled = false
                    editor.isAutomaticSpellingCorrectionEnabled = false
                    editor.insertionPointColor = NSColor(red: 0.02, green: 0.38, blue: 0.45, alpha: 1)
                }
            }
        }
    }
    func resizePanel() {
        guard panel != nil, requestedHeight != model.panelHeight else { return }
        let oldHeight = panel.frame.height
        requestedHeight = model.panelHeight
        var frame = panel.frame
        let top = panelTop > 0 ? panelTop : frame.maxY
        frame.size = NSSize(width: 580, height: model.panelHeight)
        frame.origin.y = top - frame.height
        // Layout once. Reveal the extra area on the compositor, not by reflowing
        // SwiftUI and every animated background on every window-resize tick.
        panel.setFrame(frame, display: true)
        guard let surface = panel.contentView?.layer else { return }
        surface.mask = nil
        guard panel.isVisible, frame.height > oldHeight, !departure,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let mask = CAShapeLayer()
        let end = CGPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: 42, cornerHeight: 42, transform: nil)
        let start = CGPath(roundedRect: CGRect(x: 0, y: frame.height - oldHeight, width: 580, height: oldHeight), cornerWidth: 42, cornerHeight: 42, transform: nil)
        mask.path = end; surface.mask = mask
        let reveal = CABasicAnimation(keyPath: "path")
        reveal.fromValue = start; reveal.toValue = end; reveal.duration = 0.40
        reveal.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        mask.add(reveal, forKey: "dropdown")
    }
    func hide(restoreFocus: Bool = true) {
        guard panel.isVisible else { return }
        model.panelVisible = false; model.opening = false; model.launchStarted = nil; departure = false; panel.orderOut(nil)
        panel.alphaValue = 1
        logger.notice("Search panel hidden")
        if restoreFocus { previousApp?.activate() }
    }
    func windowDidResignKey(_ notification: Notification) {
        guard !model.opening && !departure else { return }
        if notification.object as? NSWindow === panel { hide(restoreFocus: false) }
    }
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        client is GuidedSearchField ? guidedEditor : nil
    }
    func animateDeparture() {
        guard panel.isVisible else { model.opening = false; model.launchStarted = nil; return }
        departure = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { hide(restoreFocus: false); return }
        let original = panel.frame
        let destination = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let veil = NSPanel(contentRect: destination, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        veil.isOpaque = false; veil.backgroundColor = .clear; veil.hasShadow = false
        veil.level = .floating; veil.ignoresMouseEvents = true
        veil.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: destination.size))
        glass.material = .hudWindow; glass.blendingMode = .behindWindow; glass.state = .active
        glass.wantsLayer = true; veil.contentView = glass
        let startRect = original.offsetBy(dx: -destination.minX, dy: -destination.minY)
        let startPath = CGPath(roundedRect: startRect, cornerWidth: 42, cornerHeight: 42, transform: nil)
        let endPath = CGPath(roundedRect: glass.bounds, cornerWidth: 12, cornerHeight: 12, transform: nil)
        let mask = CAShapeLayer(); mask.path = endPath; glass.layer?.mask = mask
        let expansion = CABasicAnimation(keyPath: "path")
        expansion.fromValue = startPath; expansion.toValue = endPath
        expansion.duration = 0.60
        expansion.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        veil.alphaValue = 0; veil.orderFrontRegardless()
        mask.add(expansion, forKey: "boundary")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
            veil.animator().alphaValue = 0.96
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) { [weak self] in
            self?.hide(restoreFocus: false)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.36
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.3, 1)
                veil.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in veil.orderOut(nil) }
            }
        }
    }
    @objc func showSettings() {
        hide(restoreFocus: false)
        if settingsWindow == nil {
            let host = NSHostingView(rootView: SettingsView(model: model, bridge: model.bridge, back: { [weak self] in self?.settingsWindow?.orderOut(nil); self?.show() }))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 660), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Glide Settings"; window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.065, green: 0.08, blue: 0.078, alpha: 1)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host; window.setContentSize(host.fittingSize)
            window.isReleasedWhenClosed = false; window.center(); settingsWindow = window
        }
        NSApp.activate(); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return false }
    func applicationWillTerminate(_ notification: Notification) {
        model.bridge.stop()
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
}

@main enum GlideMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        if let index = CommandLine.arguments.firstIndex(of: "--export-previews"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.prohibited)
            delegate.createPanel()
            let saved = delegate.model.theme
            for theme in ["Purple", "Light Blue", "Deep Blue"] {
                delegate.model.theme = theme; delegate.model.panelVisible = true
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                if let view = delegate.panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let url = URL(fileURLWithPath: CommandLine.arguments[index + 1]).appendingPathComponent(theme + ".png")
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
            delegate.model.theme = saved
            let onboarding = NSHostingView(rootView: SettingsView(model: delegate.model, bridge: delegate.model.bridge, back: {}))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 740), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = onboarding; window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let bitmap = onboarding.bitmapImageRepForCachingDisplay(in: onboarding.bounds) {
                onboarding.cacheDisplay(in: onboarding.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]).appendingPathComponent("Onboarding.png"))
            }
            return
        }
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
