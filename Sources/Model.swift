import AppKit
import SwiftUI
import ServiceManagement

struct SearchRow: Identifiable {
    var id: String { kind + text + (url ?? "") }
    let text: String
    let kind: String
    var url: String? = nil
    var detail: String? = nil
    var icon: String { ["Recent", "Your searches", "History"].contains(kind) ? "clock.arrow.circlepath" : SearchDestination.isWebsite(text) ? "globe" : "magnifyingglass" }
}

@MainActor final class SearchModel: ObservableObject {
    let bridge = ChromeBridge()
    @Published var chromeConnected = false
    @Published var panelVisible = false
    @Published var profileDraft = "Default"
    @Published var personalRows: [SearchRow] = []
    @Published var useChromeHistory = UserDefaults.standard.object(forKey: "chromeHistory") as? Bool ?? false {
        didSet { UserDefaults.standard.set(useChromeHistory, forKey: "chromeHistory"); refresh() }
    }
    @Published var query = "" { didSet { if oldValue != query { refresh() } } }
    @Published var suggestions: [String] = []
    @Published var selected = 0
    @Published var fetching = false
    @Published var networkUnavailable = false
    @Published var error: String?
    @Published var opening = false
    @Published var launchStarted: Date?
    @Published var resultSlots = 0
    @Published var theme = UserDefaults.standard.string(forKey: "colorTheme") ?? "Purple" {
        didSet { UserDefaults.standard.set(theme, forKey: "colorTheme") }
    }
    @Published var hotkeyAvailable = true
    @Published var profile = UserDefaults.standard.string(forKey: "profile") ?? "Default" {
        didSet { UserDefaults.standard.set(profile, forKey: "profile") }
    }
    @Published var liveSuggestions = UserDefaults.standard.object(forKey: "suggestions") as? Bool ?? false {
        didSet { UserDefaults.standard.set(liveSuggestions, forKey: "suggestions"); refresh() }
    }
    @Published var rememberHistory = UserDefaults.standard.object(forKey: "rememberHistory") as? Bool ?? false {
        didSet { UserDefaults.standard.set(rememberHistory, forKey: "rememberHistory"); if !rememberHistory { clearHistory() } }
    }
    @Published var recents = UserDefaults.standard.stringArray(forKey: "recents") ?? []
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    private var request: Task<Void, Never>?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()
    var didOpen: (() -> Void)?
    var layoutChanged: (() -> Void)?
    var panelHeight: CGFloat { 136 + (text.isEmpty ? 0 : CGFloat(max(1, resultSlots)) * 44 + 12) + (error == nil ? 0 : 40) }

    func startBridge() {
        bridge.connectionChanged = { [weak self] in
            guard let self else { return }; self.chromeConnected = self.bridge.connected; self.refresh()
        }
        bridge.start()
    }
    var text: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var rows: [SearchRow] {
        if text.isEmpty { return [] }
        return [SearchRow(text: text, kind: SearchDestination.isWebsite(text) ? "Open website" : "Google Search")]
            + (chromeConnected ? personalRows : suggestions.map { SearchRow(text: $0, kind: "Google") })
    }

    func refresh() {
        request?.cancel()
        if text.isEmpty { suggestions = []; personalRows = []; resultSlots = 0 }
        selected = 0; error = nil; fetching = false; networkUnavailable = false
        layoutChanged?()
        let search = text
        guard (liveSuggestions || (chromeConnected && useChromeHistory)), !search.isEmpty, !SearchDestination.isWebsite(search) else { return }
        request = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard let self, !Task.isCancelled else { return }
                self.fetching = true
                if self.chromeConnected {
                    let result = try await self.bridge.request("suggest", payload: ["query": search, "google": self.liveSuggestions, "history": self.useChromeHistory])
                    try Task.checkCancellation()
                    guard self.text == search else { return }
                    self.personalRows = (result["rows"] as? [[String: Any]] ?? []).prefix(6).compactMap { item in
                        guard let text = item["text"] as? String, let kind = item["kind"] as? String else { return nil }
                        let url = item["url"] as? String
                        if let url, !(URL(string: url).map { ["https", "http"].contains($0.scheme ?? "") } ?? false) { return nil }
                        return SearchRow(text: text, kind: kind, url: url, detail: item["detail"] as? String)
                    }
                    self.networkUnavailable = result["googleUnavailable"] as? Bool ?? false
                    self.resultSlots = max(self.resultSlots, self.rows.count); self.fetching = false; self.layoutChanged?(); return
                }
                var parts = URLComponents(string: "https://suggestqueries.google.com/complete/search")!
                parts.queryItems = [URLQueryItem(name: "client", value: "chrome"), URLQueryItem(name: "q", value: search)]
                let (data, response) = try await self.session.data(from: parts.url!)
                try Task.checkCancellation()
                guard self.text == search else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                self.suggestions = SearchDestination.suggestions(from: data, query: search)
                self.resultSlots = max(self.resultSlots, self.rows.count); self.fetching = false; self.layoutChanged?()
            } catch {
                guard !Task.isCancelled, let self, self.text == search else { return }
                self.fetching = false; self.networkUnavailable = true; self.layoutChanged?()
            }
        }
    }

    func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selected = (selected + delta + rows.count) % rows.count
    }
    func complete() {
        guard rows.indices.contains(selected) else { return }
        query = rows[selected].text
    }
    func clearHistory() {
        recents = []; UserDefaults.standard.removeObject(forKey: "recents")
    }
    func reset() {
        request?.cancel(); resultSlots = 0; opening = false; launchStarted = nil; query = ""; suggestions = []; personalRows = []; selected = 0; error = nil; fetching = false; layoutChanged?()
    }
    func open(_ explicit: SearchRow? = nil) {
        guard !opening else { return }
        let row = explicit ?? (rows.indices.contains(selected) ? rows[selected] : SearchRow(text: text, kind: "Google"))
        guard let url = row.url.flatMap(URL.init(string:)) ?? SearchDestination.url(for: row.text) else { return }
        guard ["https", "http"].contains(url.scheme ?? "") else { return }
        request?.cancel(); fetching = false
        opening = true; launchStarted = Date(); error = nil
        Task {
            do {
                if !bridge.connected {
                    let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty
                    if !running {
                        // Launch the canonical app once through Launch Services. The companion then creates the tab.
                        let config = NSWorkspace.OpenConfiguration()
                        config.createsNewApplicationInstance = false
                        guard SearchDestination.validProfile(profile) else { throw ChromeBridgeError.message("Set your Chrome profile directory in Settings.") }
                        config.arguments = ["--profile-directory=\(profile)"]
                        _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Google Chrome.app"), configuration: config)
                        for _ in 0..<80 {
                            if bridge.connected { break }
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    }
                }
                guard bridge.connected else { throw ChromeBridgeError.disconnected }
                _ = try await bridge.request("open", payload: ["url": url.absoluteString])
                if rememberHistory {
                    recents.removeAll { $0.caseInsensitiveCompare(row.url ?? row.text) == .orderedSame }
                    recents.insert(row.url ?? row.text, at: 0); recents = Array(recents.prefix(20))
                    UserDefaults.standard.set(recents, forKey: "recents")
                }
                didOpen?()
            } catch { opening = false; launchStarted = nil; self.error = error.localizedDescription; layoutChanged?() }
        }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                error = "Approve Glide in System Settings → General → Login Items."
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { self.error = "Couldn’t update launch at login: \(error.localizedDescription)" }
    }
}
