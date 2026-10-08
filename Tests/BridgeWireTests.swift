import Foundation
import Darwin

@main enum WireTests {
    static func main() {
        var sockets: [Int32] = [0, 0]
        precondition(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        let unicode = BridgeWire.json(["query": "日本語 café 🦋"])!
        precondition(BridgeWire.writeFrame(sockets[0], data: unicode))
        precondition(BridgeWire.readFrame(sockets[1]) == unicode)
        precondition(!BridgeWire.writeFrame(sockets[0], data: Data()))
        precondition(!BridgeWire.writeFrame(sockets[0], data: Data(repeating: 0, count: BridgeWire.maximum + 1)))
        var oversized = UInt32(BridgeWire.maximum + 1).littleEndian
        withUnsafeBytes(of: &oversized) { _ = write(sockets[0], $0.baseAddress!, 4) }
        precondition(BridgeWire.readFrame(sockets[1]) == nil)
        close(sockets[0]); close(sockets[1])
        precondition(BridgeWire.address() != nil)
        print("Passed: native frame lengths, Unicode bytes, size limits, socket address")
    }
}
