import Foundation
import Darwin

// Chrome owns this background helper. Only the pinned companion origin may run it.
guard CommandLine.arguments.dropFirst().first == "chrome-extension://\(BridgeWire.extensionID)/" else { exit(1) }
signal(SIGPIPE, SIG_IGN)
let lock = NSLock()
var activeSocket: Int32 = -1

DispatchQueue.global(qos: .utility).async {
    while true {
        guard let data = try? Data(contentsOf: BridgeWire.sessionURL), let config = BridgeWire.object(data), let token = config["token"] as? String,
              var address = BridgeWire.address() else { Thread.sleep(forTimeInterval: 1); continue }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let result = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { close(fd); Thread.sleep(forTimeInterval: 1); continue }
        guard BridgeWire.writeFrame(fd, data: BridgeWire.json(["token": token])!) else { close(fd); continue }
        lock.lock(); activeSocket = fd; lock.unlock()
        guard BridgeWire.writeFrame(STDOUT_FILENO, data: BridgeWire.json(["type": "handshake"])!) else { exit(0) }
        while let command = BridgeWire.readFrame(fd) {
            if !BridgeWire.writeFrame(STDOUT_FILENO, data: command) { exit(0) }
        }
        lock.lock(); activeSocket = -1; lock.unlock(); close(fd)
        Thread.sleep(forTimeInterval: 1)
    }
}

while let response = BridgeWire.readFrame(STDIN_FILENO) {
    lock.lock()
    if activeSocket >= 0 { BridgeWire.writeFrame(activeSocket, data: response) }
    lock.unlock()
}
exit(0)
