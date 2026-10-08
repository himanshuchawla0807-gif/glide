import Foundation
import Darwin

enum BridgeWire {
    static let extensionID = "ampmdcedpokcijoakniagpieaebfooio"
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Glide")
    static let socketURL = directory.appendingPathComponent("bridge.sock")
    static let sessionURL = directory.appendingPathComponent("session.json")
    static let maximum = 64 * 1024

    static func readExact(_ fd: Int32, count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let received = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), count - offset) }
            if received < 0 && errno == EINTR { continue }
            guard received > 0 else { return nil }
            offset += received
        }
        return Data(bytes)
    }
    static func readFrame(_ fd: Int32) -> Data? {
        guard let header = readExact(fd, count: 4) else { return nil }
        let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard length > 0, length <= maximum else { return nil }
        return readExact(fd, count: Int(length))
    }
    @discardableResult static func writeFrame(_ fd: Int32, data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maximum else { return false }
        var length = UInt32(data.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(data)
        var offset = 0
        while offset < frame.count {
            let written = frame.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), frame.count - offset) }
            if written < 0 && errno == EINTR { continue }
            guard written > 0 else { return false }
            offset += written
        }
        return true
    }
    static func address() -> sockaddr_un? {
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketURL.path.utf8) + [0]
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: path) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
    static func json(_ value: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: value) }
    static func object(_ data: Data) -> [String: Any]? { try? JSONSerialization.jsonObject(with: data) as? [String: Any] }
}
