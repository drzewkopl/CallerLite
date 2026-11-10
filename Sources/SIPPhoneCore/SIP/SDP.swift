import Foundation

struct SDPMedia {
    var address: String
    var port: UInt16
    var payloadTypes: [Int]
}

enum SDP {
    /// Audio offer: PCMU (0), PCMA (8) and telephone-event (101) for DTMF.
    static func offer(localIP: String, rtpPort: UInt16, sessionID: Int, hold: Bool = false) -> String {
        [
            "v=0",
            "o=- \(sessionID) \(sessionID) IN IP4 \(localIP)",
            "s=CallerLite",
            "c=IN IP4 \(hold ? "0.0.0.0" : localIP)",
            "t=0 0",
            "m=audio \(rtpPort) RTP/AVP 0 8 101",
            "a=rtpmap:0 PCMU/8000",
            "a=rtpmap:8 PCMA/8000",
            "a=rtpmap:101 telephone-event/8000",
            "a=fmtp:101 0-16",
            "a=\(hold ? "sendonly" : "sendrecv")",
            "a=ptime:20",
        ].joined(separator: "\r\n") + "\r\n"
    }

    /// Answer with a single selected codec.
    static func answer(localIP: String, rtpPort: UInt16, chosenPT: Int, includeTelephoneEvent: Bool, sessionID: Int) -> String {
        let codec = chosenPT == 8 ? "PCMA" : "PCMU"
        var lines = [
            "v=0",
            "o=- \(sessionID) \(sessionID) IN IP4 \(localIP)",
            "s=CallerLite",
            "c=IN IP4 \(localIP)",
            "t=0 0",
            "m=audio \(rtpPort) RTP/AVP \(chosenPT)\(includeTelephoneEvent ? " 101" : "")",
            "a=rtpmap:\(chosenPT) \(codec)/8000",
        ]
        if includeTelephoneEvent {
            lines.append("a=rtpmap:101 telephone-event/8000")
            lines.append("a=fmtp:101 0-16")
        }
        lines.append("a=sendrecv")
        lines.append("a=ptime:20")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Extracts connection address, port and offered payload types.
    static func parse(_ sdp: String) -> SDPMedia? {
        var address = "0.0.0.0"
        var port: UInt16 = 0
        var pts: [Int] = []

        for raw in sdp.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("c=IN IP4 ") {
                let a = String(line.dropFirst("c=IN IP4 ".count)).trimmingCharacters(in: .whitespaces)
                if !a.isEmpty { address = a }
            } else if line.hasPrefix("m=audio") {
                let parts = line.split(separator: " ")
                guard parts.count >= 4 else { continue }
                port = UInt16(parts[1]) ?? 0
                pts = parts[3...].compactMap { Int($0) }
            }
        }
        guard !pts.isEmpty, port > 0 else { return nil }
        return SDPMedia(address: address, port: port, payloadTypes: pts)
    }

    /// PCMU preferred, PCMA fallback.
    static func chooseCodec(offered: [Int]) -> Int? {
        if offered.contains(0) { return 0 }
        if offered.contains(8) { return 8 }
        return nil
    }
}
