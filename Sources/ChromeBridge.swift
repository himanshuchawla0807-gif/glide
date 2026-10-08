import Foundation
import AppKit
import Darwin

enum ChromeBridgeError: LocalizedError {
    case disconnected, timeout, message(String)
    var errorDescription: String? {
        switch self {
        case .disconnected: return "Connect Glide Companion in your chosen Chrome profile."
        case .timeout: return "Chrome didn’t respond. Click Glide Companion in Chrome to reconnect."
        case .message(let text): return text
        }
    }
}

@MainActor final class ChromeBridge: ObservableObject {
    @Published var connected = false
    @Published var setupError: String?
    @Published var accountError: String?
    @Published var pendingPair = false
    @Published var paired = UserDefaults.standard.string(forKey: "pairedChromeID") != nil
    private var candidate: (String, Int32, UUID)?
    func approvePairing() {
        guard let (id, fd, generation) = candidate else { return }
        UserDefaults.standard.set(id, forKey: "pairedChromeID")
        paired = true; pendingPair = false; candidate = nil
        receive(["type": "hello", "profileID": id], fd: fd, generation: generation)
    }
    func unpair() {
        UserDefaults.standard.removeObject(forKey: "pairedChromeID")
        paired = false; pendingPair = false; candidate = nil
        if client >= 0 { shutdown(client, SHUT_RDWR) }
        connected = false; connectionChanged?()
    }
    private var listener: Int32 = -1
    private var client: Int32 = -1
    private var clientID = UUID()
    private let secret = UUID().uuidString + UUID().uuidString
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    var connectionChanged: (() -> Void)?

    func start() {
        signal(SIGPIPE, SIG_IGN)
        do {
            try FileManager.default.createDirectory(at: BridgeWire.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            chmod(BridgeWire.directory.path, 0o700)
            let session = BridgeWire.json(["token": secret])!
            try session.write(to: BridgeWire.sessionURL, options: .atomic); chmod(BridgeWire.sessionURL.path, 0o600)
            unlink(BridgeWire.socketURL.path)
            listener = socket(AF_UNIX, SOCK_STREAM, 0)
            guard listener >= 0, var address = BridgeWire.address() else { throw ChromeBridgeError.message("Couldn’t create Chrome connection.") }
            let bound = withUnsafePointer(to: &address) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0, listen(listener, 4) == 0 else { throw ChromeBridgeError.message("Couldn’t start Chrome connection.") }
            chmod(BridgeWire.socketURL.path, 0o600)
            let server = listener; let token = secret
            DispatchQueue.global(qos: .utility).async { [weak self] in
                while true {
                    let fd = accept(server, nil, nil)
                    if fd < 0 { if errno == EINTR { continue }; break }
                    DispatchQueue.global(qos: .utility).async {
                        // Authenticate the local transport before accepting browser data.
                        var timeout = timeval(tv_sec: 5, tv_usec: 0)
                        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                        guard let data = BridgeWire.readFrame(fd), let hello = BridgeWire.object(data), hello["token"] as? String == token else { close(fd); return }
                        timeout = timeval(tv_sec: 0, tv_usec: 0)
                        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                        let generation = UUID()
                        while let data = BridgeWire.readFrame(fd), let value = BridgeWire.object(data) {
                            Task { @MainActor [weak self] in self?.receive(value, fd: fd, generation: generation) }
                        }
                        Task { @MainActor [weak self] in self?.disconnected(generation) }
                        close(fd)
                    }
                }
            }
            registerNativeHost()
        } catch { setupError = error.localizedDescription }
    }

    func registerNativeHost(at selectedRoot: URL? = nil) {
        let root = selectedRoot ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome")
        let directory = root.appendingPathComponent("NativeMessagingHosts")
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/GlideBridge")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let manifest: [String: Any] = ["name": "com.himanshu.glide", "description": "Glide profile connection", "path": executable.path, "type": "stdio", "allowed_origins": ["chrome-extension://\(BridgeWire.extensionID)/"]]
            try BridgeWire.json(manifest)!.write(to: directory.appendingPathComponent("com.himanshu.glide.json"), options: .atomic)
            setupError = nil
        } catch { setupError = "Chrome needs folder access to finish setup. Choose its folder below." }
    }

    func chooseChromeFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Choose the Google Chrome folder to register Glide’s companion connection."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google")
        if panel.runModal() == .OK, let url = panel.url { registerNativeHost(at: url) }
    }
    func revealCompanion() {
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("Glide Companion") { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
    }
    func receive(_ value: [String: Any], fd: Int32, generation: UUID) {
        if value["type"] as? String == "pair", let id = value["profileID"] as? String, UUID(uuidString: id) != nil {
            candidate = (id, fd, generation); pendingPair = true; return
        }
        if value["type"] as? String == "hello" {
            guard let id = value["profileID"] as? String, id == UserDefaults.standard.string(forKey: "pairedChromeID") else {
                accountError = "Click the companion in your chosen Chrome profile, then approve pairing here."
                return
            }
            if client >= 0 && client != fd { shutdown(client, SHUT_RDWR) }
            client = fd; clientID = generation; connected = true; accountError = nil
            connectionChanged?(); return
        }
        guard generation == clientID, connected, let id = value["id"] as? String, let continuation = pending.removeValue(forKey: id) else { return }
        if let error = value["error"] as? String { continuation.resume(throwing: ChromeBridgeError.message(error)) }
        else { continuation.resume(returning: value) }
    }
    func disconnected(_ generation: UUID) {
        if candidate?.2 == generation { candidate = nil; pendingPair = false }
        guard generation == clientID else { return }
        client = -1; connected = false
        let requests = pending; pending.removeAll()
        for continuation in requests.values { continuation.resume(throwing: ChromeBridgeError.disconnected) }
        connectionChanged?()
    }
    func request(_ type: String, payload: [String: Any]) async throws -> [String: Any] {
        guard connected, pending.count < 32 else { throw ChromeBridgeError.disconnected }
        let id = UUID().uuidString
        var command = payload; command["type"] = type; command["id"] = id
        guard let data = BridgeWire.json(command) else { throw ChromeBridgeError.message("Invalid Chrome request.") }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            if !BridgeWire.writeFrame(client, data: data), let failed = pending.removeValue(forKey: id) { failed.resume(throwing: ChromeBridgeError.disconnected) }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(type == "open" ? 8 : 5))
                if let timedOut = self?.pending.removeValue(forKey: id) { timedOut.resume(throwing: ChromeBridgeError.timeout) }
            }
        }
    }
    func stop() {
        if client >= 0 { shutdown(client, SHUT_RDWR) }
        if listener >= 0 { shutdown(listener, SHUT_RDWR); close(listener); listener = -1 }
        unlink(BridgeWire.socketURL.path); try? FileManager.default.removeItem(at: BridgeWire.sessionURL)
    }
}
