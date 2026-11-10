import Foundation

enum SocketError: Error {
    case failed(String)
}

/// Minimal blocking BSD UDP socket with a receive thread.
/// Datagrams are delivered on `callbackQueue` (default: the global queue).
final class UDPSocket {

    private let fd: Int32
    private var thread: Thread?
    private var running = false

    var onDatagram: ((Data, String, UInt16) -> Void)?
    var callbackQueue: DispatchQueue = .global()

    init() throws {
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw SocketError.failed("socket() fehlgeschlagen") }

        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(0).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard rc == 0 else {
            Darwin.close(fd)
            throw SocketError.failed("bind() fehlgeschlagen")
        }

        // Half-second receive timeout so the loop can check `running` and exit cleanly.
        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    var localPort: UInt16 {
        var addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let rc = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard rc == 0 else { return 0 }
        return UInt16(bigEndian: addr.sin_port)
    }

    func startReceiving() {
        running = true
        let t = Thread { self.receiveLoop() } // strong on purpose: keeps the socket alive while receiving
        t.name = "UDP receive"
        t.start()
        thread = t
    }

    private func receiveLoop() {
        var buf = [UInt8](repeating: 0, count: 65536)
        while running {
            var addr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buf, buf.count, 0, $0, &len)
                }
            }
            if n <= 0 {
                if !running { break }
                continue // receive timeout
            }
            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var inAddr = addr.sin_addr
            inet_ntop(AF_INET, &inAddr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: ipBuf)
            let port = UInt16(bigEndian: addr.sin_port)
            let data = Data(buf[0..<n])
            callbackQueue.async { [weak self] in
                self?.onDatagram?(data, ip, port)
            }
        }
    }

    func send(_ data: Data, to ip: String, port: UInt16) {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        var inAddr = in_addr()
        guard inet_pton(AF_INET, ip, &inAddr) == 1 else { return }
        addr.sin_addr = inAddr
        data.withUnsafeBytes { raw in
            withUnsafePointer(to: &addr) { ap in
                ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    _ = sendto(fd, raw.baseAddress, data.count, 0, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    func shutdownSocket() {
        running = false
        Darwin.close(fd)
        thread = nil
    }

    /// Best guess for the local IP used toward the internet (no packet is sent).
    static func primaryLocalIP() -> String {
        let s = socket(AF_INET, SOCK_DGRAM, 0)
        guard s >= 0 else { return "127.0.0.1" }
        defer { Darwin.close(s) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(53).bigEndian
        guard inet_pton(AF_INET, "8.8.8.8", &addr.sin_addr) == 1 else { return "127.0.0.1" }

        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard rc == 0 else { return "127.0.0.1" }

        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let rc2 = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(s, $0, &len)
            }
        }
        guard rc2 == 0 else { return "127.0.0.1" }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var inAddr = local.sin_addr
        inet_ntop(AF_INET, &inAddr, &buf, socklen_t(INET_ADDRSTRLEN))
        let ip = String(cString: buf)
        return ip.isEmpty ? "127.0.0.1" : ip
    }
}
