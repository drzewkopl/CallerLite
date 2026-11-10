import XCTest
@testable import SIPPhoneCore

/// Mock SIP registrar/PBX on localhost exercising the full RealSIPClient flow:
/// REGISTER (digest 401 -> 200), INVITE (100/180/200 + SDP), ACK, BYE.
final class SIPIntegrationTests: XCTestCase {

    // MARK: Delegate box (strong reference; the client holds delegates weakly)

    final class DelegateBox: SIPClientDelegate {
        let lock = NSLock()
        var registered = false
        var failed: String?
        var events: [SIPCallEvent] = []
        var incomingCall: ((UUID) -> Void)?

        func sipClientDidRegister(_ client: any SIPClient) {
            lock.lock(); registered = true; lock.unlock()
        }

        func sipClient(_ client: any SIPClient, didFailRegistration reason: String) {
            lock.lock(); failed = reason; lock.unlock()
        }

        func sipClient(_ client: any SIPClient, didChangeCall callID: UUID, event: SIPCallEvent) {
            lock.lock(); events.append(event); lock.unlock()
        }

        func sipClient(_ client: any SIPClient, didReceiveIncomingCall callID: UUID, from number: String, displayName: String?) {
            incomingCall?(callID)
        }

        func snapshotEvents() -> [SIPCallEvent] {
            lock.lock(); defer { lock.unlock() }
            return events
        }
    }

    // MARK: Mock server

    final class MockSIPServer {
        let socket: UDPSocket
        let queue = DispatchQueue(label: "mock.sip")
        let lock = NSLock()

        let username = "testuser"
        let password = "testpass"
        let realm = "testrealm"
        let nonce = "n0nce1234"
        let rtpPort: UInt16 = 40000

        private(set) var authVerified = false
        private(set) var inviteAuthVerified = false
        private(set) var inviteSeen = false
        private(set) var byeSeen = false
        private(set) var ackBranchMatched = false
        private var challengedInviteBranch = ""
        private var challengedInviteCSeq = ""

        var port: UInt16 { socket.localPort }

        init() throws {
            socket = try UDPSocket()
            socket.callbackQueue = queue
            socket.onDatagram = { [weak self] data, ip, port in
                self?.handle(data, ip: ip, port: port)
            }
            socket.startReceiving()
        }

        private func handle(_ data: Data, ip: String, port: UInt16) {
            guard case .request(let req)? = SIPParser.parse(data) else { return }
            switch req.method {
            case "REGISTER":
                if let auth = req.header("Authorization") {
                    verify(auth: auth, req: req)
                    respond(req, ip: ip, port: port, status: 200, reason: "OK", extra: ["Expires: 120"])
                } else {
                    respond(req, ip: ip, port: port, status: 401, reason: "Unauthorized", extra: [
                        "WWW-Authenticate: Digest realm=\"\(realm)\", nonce=\"\(nonce)\", algorithm=MD5, qop=\"auth\"",
                    ])
                }

            case "INVITE":
                lock.lock(); inviteSeen = true; lock.unlock()
                if let auth = req.header("Proxy-Authorization") {
                    let ok = verifyDigest(auth, method: "INVITE", uri: req.requestURI)
                    lock.lock(); inviteAuthVerified = ok; lock.unlock()
                    respond(req, ip: ip, port: port, status: 100, reason: "Trying")
                    respond(req, ip: ip, port: port, status: 180, reason: "Ringing")
                    let sdp = "v=0\r\no=- 9 9 IN IP4 127.0.0.1\r\ns=-\r\nc=IN IP4 127.0.0.1\r\nt=0 0\r\n"
                        + "m=audio \(rtpPort) RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\na=sendrecv\r\n"
                    respond(req, ip: ip, port: port, status: 200, reason: "OK", body: sdp,
                            extra: ["Contact: <sip:mock@127.0.0.1:\(self.port)>"])
                } else {
                    // Challenge the INVITE and retransmit the 407 like a real
                    // server that is still waiting for the matching ACK.
                    lock.lock()
                    challengedInviteBranch = req.topViaBranch ?? ""
                    challengedInviteCSeq = req.header("CSeq") ?? ""
                    lock.unlock()
                    let extra = ["Proxy-Authenticate: Digest realm=\"\(realm)\", nonce=\"\(nonce)\", algorithm=MD5, qop=\"auth\""]
                    respond(req, ip: ip, port: port, status: 407, reason: "Proxy Authentication Required", extra: extra)
                    queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        self?.respond(req, ip: ip, port: port, status: 407,
                                      reason: "Proxy Authentication Required", extra: extra)
                    }
                }

            case "ACK":
                let branch = req.topViaBranch ?? ""
                let cseq = req.header("CSeq") ?? ""
                lock.lock()
                if !challengedInviteBranch.isEmpty,
                   branch == challengedInviteBranch,
                   cseq.hasSuffix("ACK"),
                   cseq.split(separator: " ").first == challengedInviteCSeq.split(separator: " ").first {
                    ackBranchMatched = true
                }
                lock.unlock()

            case "BYE":
                lock.lock(); byeSeen = true; lock.unlock()
                respond(req, ip: ip, port: port, status: 200, reason: "OK")

            default:
                respond(req, ip: ip, port: port, status: 200, reason: "OK")
            }
        }

        private func verify(auth: String, req: SIPRequest) {
            let ok = verifyDigest(auth, method: "REGISTER", uri: "sip:127.0.0.1:\(port)")
            lock.lock()
            authVerified = ok
            lock.unlock()
        }

        private func verifyDigest(_ auth: String, method: String, uri: String) -> Bool {
            let cnonce = param("cnonce", in: auth) ?? ""
            let nc = param("nc", in: auth) ?? ""
            let response = param("response", in: auth) ?? ""
            let ha1 = DigestAuth.md5hex("\(username):\(realm):\(password)")
            let ha2 = DigestAuth.md5hex("\(method):\(uri)")
            let expected = DigestAuth.md5hex("\(ha1):\(nonce):\(nc):\(cnonce):auth:\(ha2)")
            return response == expected
        }

        private func param(_ key: String, in value: String) -> String? {
            for raw in value.components(separatedBy: ",") {
                let kv = raw.trimmingCharacters(in: .whitespaces)
                guard let eq = kv.firstIndex(of: "=") else { continue }
                guard String(kv[..<eq]).trimmingCharacters(in: .whitespaces).lowercased() == key else { continue }
                var v = String(kv[kv.index(after: eq)...])
                if v.hasPrefix("\"") { v.removeFirst() }
                if v.hasSuffix("\"") { v.removeLast() }
                return v
            }
            return nil
        }

        private func respond(_ req: SIPRequest, ip: String, port: UInt16, status: Int, reason: String,
                             body: String? = nil, extra: [String] = []) {
            var s = "SIP/2.0 \(status) \(reason)\r\n"
            for v in req.headerValues("Via") { s += "Via: \(v)\r\n" }
            if let f = req.header("From") { s += "From: \(f)\r\n" }
            var to = req.header("To") ?? ""
            if extractParam(to, "tag") == nil { to += ";tag=mocksrv" }
            s += "To: \(to)\r\n"
            if let c = req.callID { s += "Call-ID: \(c)\r\n" }
            if let cs = req.header("CSeq") { s += "CSeq: \(cs)\r\n" }
            for e in extra { s += e + "\r\n" }
            if body != nil { s += "Content-Type: application/sdp\r\n" }
            s += "Content-Length: \(body?.utf8.count ?? 0)\r\n\r\n"
            if let b = body { s += b }
            socket.send(Data(s.utf8), to: ip, port: port)
        }
    }

    // MARK: Test

    func testRegisterCallAndBye() throws {
        let server = try MockSIPServer()
        let box = DelegateBox()
        let client = RealSIPClient()
        client.delegate = box

        let registered = expectation(description: "registered")
        DispatchQueue.global().async {
            // poll briefly until registered or failed
            for _ in 0..<100 {
                if box.registered || box.failed != nil { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            registered.fulfill()
        }

        client.connect(account: SIPAccount(
            server: "127.0.0.1",
            port: Int(server.port),
            username: server.username,
            password: server.password,
            displayName: "Test User",
            ownNumber: "100",
            registrar: "127.0.0.1:\(server.port)"
        ))

        wait(for: [registered], timeout: 12)
        XCTAssertTrue(box.registered, "Registrierung fehlgeschlagen: \(box.failed ?? "?")")
        XCTAssertTrue(server.authVerified, "Digest-Authentifizierung vom Server nicht verifiziert")

        // Outgoing call through the whole dialog flow.
        let callID = client.placeCall(to: "100")
        XCTAssertNotNil(callID)

        let connected = expectation(description: "connected")
        DispatchQueue.global().async {
            for _ in 0..<150 {
                if box.snapshotEvents().contains(.connected) { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            connected.fulfill()
        }
        wait(for: [connected], timeout: 16)

        let events = box.snapshotEvents()
        XCTAssertTrue(events.contains(.ringing), "Events: \(events)")
        XCTAssertTrue(events.contains(.connected), "Events: \(events)")
        XCTAssertTrue(server.inviteSeen)
        XCTAssertTrue(server.inviteAuthVerified, "INVITE-Digest vom Server nicht verifiziert")
        XCTAssertTrue(server.ackBranchMatched, "ACK auf 407 nutzt nicht die INVITE-Branch")

        // The retransmitted 407 must not end the call (regression guard).
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertFalse(box.snapshotEvents().contains(.ended), "Anruf wurde durch 407-Wiederholung beendet")

        client.end(callID: callID!)

        let bye = expectation(description: "bye")
        DispatchQueue.global().async {
            for _ in 0..<80 {
                if box.snapshotEvents().contains(.ended) { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            bye.fulfill()
        }
        wait(for: [bye], timeout: 10)

        XCTAssertTrue(box.snapshotEvents().contains(.ended))
        XCTAssertTrue(server.byeSeen, "BYE wurde vom Server nicht empfangen")

        client.disconnect()
    }
}
