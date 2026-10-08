import SwiftUI
import AppKit

private let mint = Color(red: 0.78, green: 0.69, blue: 1)
private let muted = Color.white.opacity(0.48)

struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label).font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.62)).padding(.horizontal, 6).padding(.vertical, 3)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.09)))
    }
}

struct GlideMark: View {
    var body: some View {
        Image(systemName: "arrow.up.right").font(.system(size: 19, weight: .semibold))
            .foregroundStyle(mint).frame(width: 36, height: 36)
            .background(mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(mint.opacity(0.16)))
    }
}

struct SearchPanelView: View {
    @ObservedObject var model: SearchModel
    let settings: () -> Void
    let dismiss: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ZStack {

                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.5)).frame(width: 24, height: 28)
                    Spacer()
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications/Google Chrome.app")).resizable().frame(width: 13, height: 13)
                        Text("Chrome").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                        Circle().fill(model.chromeConnected ? Color(red: 0.64, green: 0.83, blue: 0.72) : .white.opacity(0.28)).frame(width: 4, height: 4)
                    }.padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.white.opacity(0.22), in: Capsule())
                    Button(action: settings) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.35))
                            .frame(width: 22, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Close").accessibilityLabel("Close search")
                }
            }.frame(height: 46).padding(.horizontal, 22).padding(.top, 5)

            HStack(spacing: 15) {
                CircularStrands(active: model.panelVisible).frame(width: 42, height: 42)

                SearchInput(model: model).frame(maxWidth: .infinity).frame(height: 42)
                if model.fetching || model.opening || model.networkUnavailable {
                    NativeLatticeLoader(working: model.fetching || model.opening, failed: model.networkUnavailable)
                }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.3))
                    }.buttonStyle(.plain).help("Clear").accessibilityLabel("Clear search")
                }
            }.padding(.horizontal, 22).frame(height: 72)
                .overlay { if let started = model.launchStarted { LaunchSweep(started: started).allowsHitTesting(false).accessibilityHidden(true) } }

            if !model.rows.isEmpty {
                Rectangle().fill(.white.opacity(0.065)).frame(height: 1).padding(.horizontal, 22)
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        Button { model.open(row) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: row.icon).font(.system(size: 13)).foregroundStyle(index == model.selected ? Color(red: 0.45, green: 0.87, blue: 0.93) : .white.opacity(0.38)).frame(width: 25)
                                Text(row.text).font(.system(size: 14, weight: index == model.selected ? .medium : .regular))
                                    .foregroundStyle(.white.opacity(index == model.selected ? 0.94 : 0.67)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(row.detail ?? row.kind).font(.system(size: 10)).foregroundStyle(.white.opacity(0.32)).lineLimit(1).frame(maxWidth: 130, alignment: .trailing)
                                if index == model.selected {
                                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                                }
                            }.padding(.horizontal, 12).frame(height: 40).contentShape(Rectangle())
                                .background(index == model.selected ? .white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityLabel("\(row.kind): \(row.text)").padding(.vertical, 2)
                    }
                }.padding(.horizontal, 10).padding(.top, 7)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.22), value: model.rows.map(\.id))
            }
            if let error = model.error {
                HStack {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
                    Spacer()
                    if !model.chromeConnected { Button("Connect") { settings() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8)) }
                }.padding(.horizontal, 22).frame(height: 40)
            }
            Spacer(minLength: 0)
        }.frame(width: 580).frame(maxHeight: .infinity, alignment: .top)

            .blur(radius: model.opening ? 16 : 0)
            .animation(.easeInOut(duration: 0.38), value: model.opening)
            .background { ZStack { (model.theme == "Black" ? Color.black : model.theme == "Graphite" ? Color(white: 0.065) : model.theme == "Purple" ? Color(red: 0.065, green: 0.05, blue: 0.095) : Color(red: 0.025, green: 0.045, blue: 0.08)); NativeMicroSlats(active: model.panelVisible, theme: model.theme) } }
            .clipShape(RoundedRectangle(cornerRadius: 42))
            .overlay(RoundedRectangle(cornerRadius: 42).stroke(LinearGradient(colors: [.white.opacity(0.19), .white.opacity(0.055)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

struct SearchInput: NSViewRepresentable {
    @ObservedObject var model: SearchModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSTextField {
        let field = GuidedSearchField()
        field.isEditable = true; field.isSelectable = true
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 24, weight: .regular); field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(string: "Search", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.35), .font: NSFont.systemFont(ofSize: 24)])
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search the web")
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.query { field.stringValue = model.query }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: SearchModel
        init(_ model: SearchModel) { self.model = model }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.query = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            if textView.hasMarkedText() { return false }
            switch command {
            case #selector(NSResponder.moveDown(_:)): model.move(1); return true
            case #selector(NSResponder.moveUp(_:)): model.move(-1); return true
            case #selector(NSResponder.insertNewline(_:)): model.open(); return true
            case #selector(NSResponder.insertTab(_:)): model.complete(); return true
            default: return false
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var bridge: ChromeBridge
    let back: () -> Void
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack {
                NativeTechText(active: false).frame(width: 103, height: 36)
                Spacer()
                Button("Back to search", action: back).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(muted)
            }
            if !bridge.paired {
                HStack(spacing: 16) {
                    CircularStrands(active: true).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your browser. Your space.").font(.system(size: 23, weight: .semibold, design: .rounded))
                        Text("Pair Chrome once. Search from anywhere. Everything stays on your Mac unless you choose an online search.").font(.system(size: 12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.vertical, 6)
            }
            card {
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications/Google Chrome.app")).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Chrome profile").font(.system(size: 14, weight: .medium))
                        Text(bridge.paired ? "Paired locally on this Mac" : "No profile paired").font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Spacer()
                    Circle().fill(bridge.connected ? Color.green.opacity(0.7) : Color.orange.opacity(0.7)).frame(width: 6, height: 6)
                }
                Text(bridge.connected ? "Connected to your profile. Cookies stay inside Chrome." : "Connect Chrome once for personal suggestions and tabs in this profile.")
                    .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                if !bridge.connected {
                    Text("1. Open chrome://extensions in your chosen Chrome profile.\n2. Enable Developer mode, choose Load unpacked, and select the companion folder below.\n3. Click Glide Companion in Chrome’s toolbar, then approve pairing here.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Show companion folder") { bridge.revealCompanion() }
                        if bridge.setupError != nil { Button("Choose Chrome folder") { bridge.chooseChromeFolder() } }
                    }.font(.system(size: 11))
                }
                if bridge.pendingPair {
                    Text("A Chrome profile is requesting to connect. Approve only if you just clicked Glide Companion in the profile you want.").font(.system(size: 11)).foregroundStyle(muted)
                    Button("Approve this Chrome profile") { bridge.approvePairing() }.buttonStyle(.borderedProminent)
                }
                if bridge.paired { Button("Disconnect profile") { bridge.unpair() }.font(.system(size: 11)) }
                TextField("Chrome profile directory (Default or Profile 1)", text: $model.profile).textFieldStyle(.roundedBorder)
                Text("For cold start, enter Profile Path’s last folder from chrome://version in your chosen profile.").font(.system(size: 10)).foregroundStyle(muted)
                if let error = bridge.setupError ?? bridge.accountError { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            }
            card {
                Picker("Appearance", selection: $model.theme) {
                    Text("Purple").tag("Purple")
                    Text("Light Blue").tag("Light Blue")
                    Text("Deep Blue").tag("Deep Blue")
                    Text("Black").tag("Black")
                    Text("Graphite").tag("Graphite")
                    Text("Midnight").tag("Midnight")
                    Text("Rose").tag("Rose")
                }.pickerStyle(.menu)
            }
            card {
                Toggle("Google suggestions", isOn: $model.liveSuggestions).toggleStyle(.switch).controlSize(.small)
                Text("Uses your signed-in Google session when Chrome is connected.")
                    .font(.system(size: 11)).foregroundStyle(muted)
                Divider().padding(.vertical, 2)
                Toggle("Suggestions from Chrome history", isOn: $model.useChromeHistory).toggleStyle(.switch).controlSize(.small)
                Text("Previous searches and visited pages from your paired profile.")
                    .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                Divider().padding(.vertical, 2)
                Toggle("Remember Glide searches", isOn: $model.rememberHistory).toggleStyle(.switch).controlSize(.small)
                HStack {
                    Text("Stored only on this Mac.").font(.system(size: 11)).foregroundStyle(muted)
                    Spacer(); Button("Clear") { model.clearHistory(); model.layoutChanged?() }.font(.system(size: 11)).disabled(model.recents.isEmpty)
                }
                Divider().padding(.vertical, 2)
                Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).toggleStyle(.switch).controlSize(.small)
            }
            if !model.hotkeyAvailable { Text("Shift + Space is already in use by another app.").font(.system(size: 11)).foregroundStyle(.orange) }
            HStack { Text("1.3"); Spacer(); Text("Private by design.") }.font(.system(size: 10)).foregroundStyle(muted)
        }.padding(28).frame(width: 520).foregroundStyle(.white.opacity(0.9))
            .background(Color(red: 0.06, green: 0.052, blue: 0.078)).environment(\.colorScheme, .dark) }.frame(width: 560, height: 740)
    }
    func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content).padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.075)))
    }
}
