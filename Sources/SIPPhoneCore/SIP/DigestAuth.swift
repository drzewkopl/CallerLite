import Foundation
import CryptoKit

struct DigestChallenge {
    var realm: String
    var nonce: String
    var algorithm: String
    var qop: String?
    var opaque: String?

    static func parse(_ value: String) -> DigestChallenge? {
        var v = value.trimmingCharacters(in: .whitespaces)
        let lower = v.lowercased()
        if lower.hasPrefix("digest ") {
            v = String(v.dropFirst("digest ".count))
        } else if lower.hasPrefix("digest") {
            v = String(v.dropFirst("digest".count))
        }
        guard let realm = param("realm", in: v),
              let nonce = param("nonce", in: v) else { return nil }
        return DigestChallenge(
            realm: realm,
            nonce: nonce,
            algorithm: param("algorithm", in: v) ?? "MD5",
            qop: param("qop", in: v),
            opaque: param("opaque", in: v)
        )
    }

    private static func param(_ key: String, in value: String) -> String? {
        for raw in value.components(separatedBy: ",") {
            let kv = raw.trimmingCharacters(in: .whitespaces)
            guard let eq = kv.firstIndex(of: "=") else { continue }
            let k = String(kv[..<eq]).trimmingCharacters(in: .whitespaces).lowercased()
            guard k == key.lowercased() else { continue }
            var v = String(kv[kv.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("\"") { v.removeFirst() }
            if v.hasSuffix("\"") { v.removeLast() }
            return v
        }
        return nil
    }
}

enum DigestAuth {
    static func md5hex(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func authorize(username: String,
                          password: String,
                          method: String,
                          uri: String,
                          challenge: DigestChallenge,
                          cnonce: String,
                          nc: String,
                          proxy: Bool = false) -> String {
        let useSHA = challenge.algorithm.uppercased().contains("SHA")
        let H = useSHA ? sha256hex : md5hex

        let ha1 = H("\(username):\(challenge.realm):\(password)")
        let ha2 = H("\(method):\(uri)")

        var fields: [String] = [
            "username=\"\(username)\"",
            "realm=\"\(challenge.realm)\"",
            "nonce=\"\(challenge.nonce)\"",
            "uri=\"\(uri)\"",
            "algorithm=\(challenge.algorithm)",
        ]

        let response: String
        if challenge.qop?.lowercased().contains("auth") == true {
            response = H("\(ha1):\(challenge.nonce):\(nc):\(cnonce):auth:\(ha2)")
            fields.append("cnonce=\"\(cnonce)\"")
            fields.append("nc=\(nc)")
            fields.append("qop=auth")
        } else {
            response = H("\(ha1):\(challenge.nonce):\(ha2)")
        }
        fields.append("response=\"\(response)\"")
        if let op = challenge.opaque, !op.isEmpty {
            fields.append("opaque=\"\(op)\"")
        }

        return (proxy ? "Proxy-" : "") + "Digest " + fields.joined(separator: ", ")
    }
}
