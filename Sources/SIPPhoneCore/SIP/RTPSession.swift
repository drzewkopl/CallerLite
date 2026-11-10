import Foundation

// MARK: - Packet building / parsing

enum RTPPacket {
    static func build(pt: UInt8, marker: Bool, seq: UInt16, ts: UInt32, ssrc: UInt32, payload: Data) -> Data {
        var d = Data(capacity: 12 + payload.count)
        d.append(0x80)
        d.append((marker ? 0x80 : 0x00) | (pt & 0x7F))
        d.append(UInt8((seq >> 8) & 0xFF))
        d.append(UInt8(seq & 0xFF))
        d.append(UInt8((ts >> 24) & 0xFF))
        d.append(UInt8((ts >> 16) & 0xFF))
        d.append(UInt8((ts >> 8) & 0xFF))
        d.append(UInt8(ts & 0xFF))
        d.append(UInt8((ssrc >> 24) & 0xFF))
        d.append(UInt8((ssrc >> 16) & 0xFF))
        d.append(UInt8((ssrc >> 8) & 0xFF))
        d.append(UInt8(ssrc & 0xFF))
        d.append(payload)
        return d
    }

    static func parse(_ data: Data) -> (pt: UInt8, seq: UInt16, ts: UInt32, ssrc: UInt32, payload: Data)? {
        guard data.count >= 12 else { return nil }
        let b0 = data[0]
        guard b0 >> 6 == 2 else { return nil } // RTP version

        let pt = data[1] & 0x7F
        guard pt < 64 || (pt >= 96 && pt <= 127) else { return nil } // drop RTCP (200+) etc.

        var idx = 12 + Int(b0 & 0x0F) * 4 // CSRC count
        if b0 & 0x10 != 0 { // header extension
            guard data.count >= idx + 4 else { return nil }
            let extWords = Int(data[idx + 2]) << 8 | Int(data[idx + 3])
            idx += 4 + extWords * 4
        }
        guard data.count > idx else { return nil }

        let seq = UInt16(data[2]) << 8 | UInt16(data[3])
        let ts = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        let ssrc = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 | UInt32(data[10]) << 8 | UInt32(data[11])
        return (pt, seq, ts, ssrc, data.subdata(in: idx..<data.count))
    }
}

// MARK: - Session

final class RTPSession {
    private let socket: UDPSocket
    private(set) var localPort: UInt16

    private var remoteIP: String?
    private var remotePort: UInt16 = 0

    private var ssrc = UInt32.random(in: 1..<UInt32.max)
    private var seq = UInt16.random(in: 0..<UInt16.max)
    private var ts = UInt32.random(in: 0..<UInt32.max)
    private var firstPacket = true

    var sendPT: UInt8 = 0
    /// (payload type, payload bytes) for G.711 audio (pt 0 or 8).
    var onAudio: ((UInt8, Data) -> Void)?

    private let callbackQueue = DispatchQueue(label: "sip.rtp")

    init?() {
        guard let s = try? UDPSocket() else { return nil }
        socket = s
        localPort = s.localPort
        s.callbackQueue = callbackQueue
        s.onDatagram = { [weak self] data, _, _ in
            guard let self, let pkt = RTPPacket.parse(data),
                  pkt.pt == 0 || pkt.pt == 8 else { return }
            self.onAudio?(pkt.pt, pkt.payload)
        }
        s.startReceiving()
    }

    func setRemote(ip: String, port: UInt16) {
        remoteIP = ip
        remotePort = port
    }

    /// samples: 8 kHz mono float frames (typically 160 = 20 ms).
    func sendAudio(samples: [Float]) {
        guard let ip = remoteIP, remotePort > 0, !samples.isEmpty else { return }
        let payload = sendPT == 8 ? G711.alawEncode(samples) : G711.ulawEncode(samples)
        let marker = firstPacket
        firstPacket = false
        seq &+= 1
        ts &+= UInt32(samples.count)
        let pkt = RTPPacket.build(pt: sendPT, marker: marker, seq: seq, ts: ts, ssrc: ssrc, payload: payload)
        socket.send(pkt, to: ip, port: remotePort)
    }

    func close() {
        socket.shutdownSocket()
    }
}
