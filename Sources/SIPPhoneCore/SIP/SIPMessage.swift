import Foundation

// MARK: - Message types

struct SIPRequest {
    var method: String
    var requestURI: String
    var headers: [(String, String)] = []
    var body: String? = nil
}

struct SIPResponse {
    var statusCode: Int
    var reason: String
    var headers: [(String, String)] = []
    var body: String? = nil
}

enum SIPIncoming {
    case request(SIPRequest)
    case response(SIPResponse)
}

// MARK: - Header accessors

protocol SIPHeaderContainer {
    var headers: [(String, String)] { get }
}

extension SIPHeaderContainer {
    func header(_ name: String) -> String? {
        headers.first { $0.0.lowercased() == name.lowercased() }?.1
    }

    func headerValues(_ name: String) -> [String] {
        headers.filter { $0.0.lowercased() == name.lowercased() }.map(\.1)
    }

    var callID: String? { header("Call-ID") }
    var viaList: [String] { headerValues("Via") }
    var topViaBranch: String? { viaList.first.flatMap { extractParam($0, "branch") } }
    var fromTag: String? { header("From").flatMap { extractParam($0, "tag") } }
    var toTag: String? { header("To").flatMap { extractParam($0, "tag") } }
    var cseqNumber: Int? { header("CSeq").flatMap { Int($0.split(separator: " ").first ?? "") } }
    var cseqMethod: String? {
        guard let cs = header("CSeq") else { return nil }
        let parts = cs.split(separator: " ")
        return parts.count > 1 ? String(parts[1]).uppercased() : nil
    }
}

extension SIPRequest: SIPHeaderContainer {}
extension SIPResponse: SIPHeaderContainer {}

// MARK: - URI / parameter helpers

func extractParam(_ value: String, _ param: String) -> String? {
    let lowered = value.lowercased()
    let needle = ";" + param.lowercased() + "="
    guard let r = lowered.range(of: needle) else { return nil }
    var v = String(value[r.upperBound...])
    if let semi = v.firstIndex(of: ";") { v = String(v[..<semi]) }
    return v.trimmingCharacters(in: .whitespaces)
}

func angleStrip(_ uri: String) -> String {
    var u = uri.trimmingCharacters(in: .whitespaces)
    if u.hasPrefix("<") { u.removeFirst() }
    if u.hasSuffix(">") { u.removeLast() }
    return u
}

enum SIPURIHelpers {
    /// `"Display" <sip:user@host;params>` / `sip:user@host` -> "user"
    static func userPart(of uriOrHeader: String) -> String {
        var s = uriOrHeader
        if let lt = s.firstIndex(of: "<"), let gt = s.lastIndex(of: ">"), lt < gt {
            s = String(s[s.index(after: lt)..<gt])
        }
        if let semi = s.firstIndex(of: ";") { s = String(s[..<semi]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[s.index(after: colon)...]) }
        if let at = s.firstIndex(of: "@") { s = String(s[..<at]) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// `"Display Name" <sip:x@y>` -> "Display Name"
    static func displayName(of headerValue: String) -> String? {
        guard let lt = headerValue.firstIndex(of: "<") else { return nil }
        let d = String(headerValue[..<lt]).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return d.isEmpty ? nil : d
    }

    static func normalizeTarget(_ number: String, server: String) -> String {
        var n = number.replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
        if n.isEmpty { n = "anonymous" }
        if !n.lowercased().hasPrefix("sip:") { n = "sip:\(n)@\(server)" }
        return angleStrip(n)
    }
}

// MARK: - Wire format

enum SIPWire {
    static func serializeRequest(_ req: SIPRequest) -> String {
        var s = "\(req.method) \(req.requestURI) SIP/2.0\r\n"
        for (n, v) in req.headers { s += "\(n): \(v)\r\n" }
        if req.header("Content-Length") == nil {
            s += "Content-Length: \(req.body?.utf8.count ?? 0)\r\n"
        }
        s += "\r\n"
        if let b = req.body { s += b }
        return s
    }

    static func serializeResponse(_ resp: SIPResponse) -> String {
        var s = "SIP/2.0 \(resp.statusCode) \(resp.reason)\r\n"
        for (n, v) in resp.headers { s += "\(n): \(v)\r\n" }
        if resp.header("Content-Length") == nil {
            s += "Content-Length: \(resp.body?.utf8.count ?? 0)\r\n"
        }
        s += "\r\n"
        if let b = resp.body { s += b }
        return s
    }
}

// MARK: - Parser

enum SIPParser {
    static func parse(_ data: Data) -> SIPIncoming? {
        guard data.count > 4 else { return nil } // keepalives etc.
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    static func parse(_ text: String) -> SIPIncoming? {
        var head = text
        var body: String? = nil

        if let r = text.range(of: "\r\n\r\n") {
            head = String(text[..<r.lowerBound])
            body = String(text[r.upperBound...])
        } else if let r = text.range(of: "\n\n") {
            head = String(text[..<r.lowerBound])
            body = String(text[r.upperBound...])
        }

        let lines = head.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let first = lines.first, !first.isEmpty else { return nil }

        var parsed: [(String, String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !parsed.isEmpty {
                parsed[parsed.count - 1].1 += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let c = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<c]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: c)...]).trimmingCharacters(in: .whitespaces)
            parsed.append((name, value))
        }

        if first.hasPrefix("SIP/") {
            let parts = first.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2, let code = Int(parts[1]) else { return nil }
            let reason = parts.count > 2 ? String(parts[2]).trimmingCharacters(in: .whitespaces) : ""
            return .response(SIPResponse(statusCode: code, reason: reason, headers: parsed, body: body))
        } else {
            let parts = first.split(separator: " ")
            guard parts.count >= 3 else { return nil }
            return .request(SIPRequest(method: String(parts[0]).uppercased(),
                                       requestURI: String(parts[1]),
                                       headers: parsed,
                                       body: body))
        }
    }
}
