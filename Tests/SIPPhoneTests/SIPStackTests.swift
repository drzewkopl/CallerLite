import XCTest
import AppKit
@testable import SIPPhoneCore

final class SIPStackTests: XCTestCase {

    // MARK: SIP messages

    func testRequestRoundTrip() {
        var req = SIPRequest(method: "INVITE", requestURI: "sip:100@asterisk.example")
        req.headers = [
            ("Via", "SIP/2.0/UDP 10.0.0.5:5060;rport;branch=z9hG4bBK1234"),
            ("From", "\"Ada\" <sip:ada@ex.com>;tag=abc"),
            ("To", "<sip:bob@ex.com>"),
            ("Call-ID", "cid123"),
            ("CSeq", "1 INVITE"),
        ]
        req.body = "v=0"

        let text = SIPWire.serializeRequest(req)
        guard case .request(let parsed)? = SIPParser.parse(Data(text.utf8)) else {
            return XCTFail("Parsung fehlgeschlagen")
        }
        XCTAssertEqual(parsed.method, "INVITE")
        XCTAssertEqual(parsed.requestURI, "sip:100@asterisk.example")
        XCTAssertEqual(parsed.callID, "cid123")
        XCTAssertEqual(parsed.fromTag, "abc")
        XCTAssertEqual(parsed.topViaBranch, "z9hG4bBK1234")
        XCTAssertEqual(parsed.cseqMethod, "INVITE")
        XCTAssertEqual(parsed.cseqNumber, 1)
        XCTAssertEqual(parsed.body, "v=0")
        XCTAssertTrue(text.contains("Content-Length: 3"))
    }

    func testResponseParsing() {
        let text = """
        SIP/2.0 401 Unauthorized\r
        Via: SIP/2.0/UDP 1.2.3.4:5060;branch=z9hG4bBX\r
        From: <sip:a@b>;tag=t1\r
        To: <sip:a@b>\r
        Call-ID: c1\r
        CSeq: 1 REGISTER\r
        WWW-Authenticate: Digest realm="asterisk",nonce="abc123",algorithm=MD5,qop="auth"\r
        Content-Length: 0\r

        """
        guard case .response(let r)? = SIPParser.parse(Data(text.utf8)) else {
            return XCTFail("Parsing fehlgeschlagen")
        }
        XCTAssertEqual(r.statusCode, 401)
        XCTAssertEqual(r.callID, "c1")
        XCTAssertEqual(r.cseqMethod, "REGISTER")
        let challenge = DigestChallenge.parse(r.header("WWW-Authenticate")!)
        XCTAssertEqual(challenge?.realm, "asterisk")
        XCTAssertEqual(challenge?.nonce, "abc123")
        XCTAssertEqual(challenge?.algorithm, "MD5")
        XCTAssertEqual(challenge?.qop, "auth")
    }

    func testHeaderParamExtraction() {
        let via = "SIP/2.0/UDP 10.0.0.5:5060;rport;branch=z9hG4bBabc"
        XCTAssertEqual(extractParam(via, "branch"), "z9hG4bBabc")
        XCTAssertNil(extractParam(via, "tag"))

        let from = "\"Bob\" <sip:bob@x>;tag=xyz123"
        XCTAssertEqual(extractParam(from, "tag"), "xyz123")
        XCTAssertEqual(SIPURIHelpers.displayName(of: from), "Bob")
        XCTAssertEqual(SIPURIHelpers.userPart(of: from), "bob")
        XCTAssertEqual(SIPURIHelpers.normalizeTarget("+49 221 4710113", server: "pbx.example"), "sip:+492214710113@pbx.example")
    }

    // MARK: Digest auth (RFC 2617 reference vector)

    func testDigestAuthRFC2617() {
        let challenge = DigestChallenge(
            realm: "testrealm@host.com",
            nonce: "dcd98b7102dd2f0e8b11d0f600bfb0c093",
            algorithm: "MD5",
            qop: "auth",
            opaque: nil
        )
        let auth = DigestAuth.authorize(
            username: "Mufasa",
            password: "Circle Of Life",
            method: "GET",
            uri: "/dir/index.html",
            challenge: challenge,
            cnonce: "0a4f113b",
            nc: "00000001"
        )
        XCTAssertTrue(auth.contains("response=\"6629fae49393a05397450978507c4ef1\""), "falsige Response: \(auth)")
        XCTAssertTrue(auth.hasPrefix("Digest "))
    }

    func testDigestAuthNoQop() {
        let challenge = DigestChallenge(
            realm: "testrealm@host.com",
            nonce: "abc",
            algorithm: "MD5",
            qop: nil,
            opaque: "opaquevalue"
        )
        let auth = DigestAuth.authorize(
            username: "u", password: "p", method: "REGISTER",
            uri: "sip:x", challenge: challenge, cnonce: "cn", nc: "00000001"
        )
        XCTAssertFalse(auth.contains("qop="))
        XCTAssertTrue(auth.contains("opaque=\"opaquevalue\""))
        // HA1 = MD5("u:testrealm@host.com:p"), HA2 = MD5("REGISTER:sip:x")
        let ha1 = DigestAuth.md5hex("u:testrealm@host.com:p")
        let ha2 = DigestAuth.md5hex("REGISTER:sip:x")
        let expected = DigestAuth.md5hex("\(ha1):abc:\(ha2)")
        XCTAssertTrue(auth.contains("response=\"\(expected)\""))
    }

    // MARK: G.711

    func testULawVectors() {
        XCTAssertEqual(G711.ulawDecode(0xFF), 0)   // +0
        XCTAssertEqual(G711.ulawDecode(0x7F), 0)   // -0
        XCTAssertEqual(G711.ulawDecode(0x80), 32124) // positive maximum
        XCTAssertEqual(G711.ulawEncode(linear: 0), 0xFF)
    }

    func testULawRoundTrip() {
        for x in stride(from: -20000, through: 20000, by: 997) {
            let u = G711.ulawEncode(linear: Int32(x))
            let back = Int(G711.ulawDecode(u))
            XCTAssertLessThanOrEqual(abs(back - x), 700, "x=\(x) u=\(u) back=\(back)")
        }
    }

    func testALawVectors() {
        XCTAssertEqual(G711.alawDecode(0xD5), 8)
        XCTAssertEqual(G711.alawDecode(0x55), -8)
    }

    func testALawRoundTrip() {
        for x in stride(from: -20000, through: 20000, by: 997) {
            let a = G711.alawEncode(linear: Int32(x))
            let back = Int(G711.alawDecode(a))
            XCTAssertLessThanOrEqual(abs(back - x), 700, "x=\(x) a=\(a) back=\(back)")
        }
    }

    // MARK: SDP

    func testSDPParsing() {
        let offer = "v=0\r\no=- 1 1 IN IP4 10.1.2.3\r\ns=-\r\nc=IN IP4 10.1.2.3\r\nt=0 0\r\nm=audio 17300 RTP/AVP 0 8 101\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:8 PCMA/8000\r\n"
        guard let m = SDP.parse(offer) else { return XCTFail("SDP nicht geparst") }
        XCTAssertEqual(m.address, "10.1.2.3")
        XCTAssertEqual(m.port, 17300)
        XCTAssertEqual(m.payloadTypes, [0, 8, 101])
        XCTAssertEqual(SDP.chooseCodec(offered: m.payloadTypes), 0)
        XCTAssertEqual(SDP.chooseCodec(offered: [8, 101]), 8)
        XCTAssertNil(SDP.chooseCodec(offered: [101, 97]))
    }

    func testSDPAnswer() {
        let answer = SDP.answer(localIP: "192.168.1.9", rtpPort: 4000, chosenPT: 0, includeTelephoneEvent: true, sessionID: 42)
        XCTAssertTrue(answer.contains("m=audio 4000 RTP/AVP 0 101"))
        XCTAssertTrue(answer.contains("c=IN IP4 192.168.1.9"))
        XCTAssertTrue(answer.contains("a=rtpmap:0 PCMU/8000"))
        XCTAssertTrue(answer.contains("a=sendrecv"))
    }

    // MARK: RTP

    func testRTPPacketRoundTrip() {
        let payload = Data([1, 2, 3, 4, 5])
        let pkt = RTPPacket.build(pt: 0, marker: true, seq: 0x1234, ts: 0x11223344, ssrc: 0x55667788, payload: payload)
        guard let parsed = RTPPacket.parse(pkt) else { return XCTFail("RTP nicht geparst") }
        XCTAssertEqual(parsed.pt, 0)
        XCTAssertEqual(parsed.seq, 0x1234)
        XCTAssertEqual(parsed.ts, 0x11223344)
        XCTAssertEqual(parsed.ssrc, 0x55667788)
        XCTAssertEqual(parsed.payload, payload)
    }

    func testRTPSkipsCSRC() {
        var pkt = RTPPacket.build(pt: 8, marker: false, seq: 1, ts: 2, ssrc: 3, payload: Data([9, 9]))
        pkt[0] = 0x80 | 0x01 // 1 CSRC
        pkt.insert(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD], at: 12)
        guard let parsed = RTPPacket.parse(pkt) else { return XCTFail("RTP nicht geparst") }
        XCTAssertEqual(parsed.pt, 8)
        XCTAssertEqual(parsed.payload, Data([9, 9]))
    }

    func testRTPRejectsRTCP() {
        var pkt = RTPPacket.build(pt: 0, marker: false, seq: 1, ts: 2, ssrc: 3, payload: Data([0]))
        pkt[1] = 200 // RTCP SR payload type
        XCTAssertNil(RTPPacket.parse(pkt))
    }

    func testRegistrarHostPortParsing() {
        var r = RealSIPHelpers.splitHostPort("registrar.example.com", defaultPort: 5060)
        XCTAssertEqual(r.host, "registrar.example.com")
        XCTAssertEqual(r.port, 5060)

        r = RealSIPHelpers.splitHostPort("registrar.example.com:5080", defaultPort: 5060)
        XCTAssertEqual(r.host, "registrar.example.com")
        XCTAssertEqual(r.port, 5080)

        r = RealSIPHelpers.splitHostPort("10.0.0.5:5061", defaultPort: 5060)
        XCTAssertEqual(r.host, "10.0.0.5")
        XCTAssertEqual(r.port, 5061)

        // Not a valid port suffix: keep whole string as host.
        r = RealSIPHelpers.splitHostPort("registrar:abc", defaultPort: 5060)
        XCTAssertEqual(r.host, "registrar:abc")
        XCTAssertEqual(r.port, 5060)
    }

    // MARK: Contact avatars

    func testContactDecodesLegacyJSONWithoutAvatar() throws {
        let json = #"[{"id":"11111111-1111-1111-1111-111111111111","firstName":"Ada","lastName":"Lovelace","company":"Analytical","number":"+49 221 5550100","isFavorite":true,"colorSeed":2}]"#
        let contacts = try JSONDecoder().decode([Contact].self, from: Data(json.utf8))
        XCTAssertEqual(contacts.count, 1)
        XCTAssertNil(contacts[0].avatar)
        XCTAssertEqual(contacts[0].displayName, "Ada Lovelace")
    }

    func testContactAvatarRoundTrip() throws {
        var contact = Contact(firstName: "Ada", lastName: "Lovelace", company: nil, number: "1")
        contact.avatar = ContactAvatar(kind: .emoji, value: "🧑")

        let data = try JSONEncoder().encode(contact)
        let decoded = try JSONDecoder().decode(Contact.self, from: data)

        XCTAssertEqual(decoded.avatar?.kind, .emoji)
        XCTAssertEqual(decoded.avatar?.value, "🧑")
    }

    func testContactImageAvatarRoundTrip() throws {
        var contact = Contact(firstName: "Ada", lastName: "Lovelace", company: nil, number: "1")
        contact.avatar = ContactAvatar(kind: .image, value: "avatar.png")

        let data = try JSONEncoder().encode(contact)
        let decoded = try JSONDecoder().decode(Contact.self, from: data)

        XCTAssertEqual(decoded.avatar, ContactAvatar(kind: .image, value: "avatar.png"))
    }

    func testAvatarImageImportScalesAndDeletes() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")

        let image = NSImage(size: NSSize(width: 200, height: 100))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 100).fill()
        image.unlockFocus()
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let filename = try XCTUnwrap(AvatarStorage.importImage(from: source))
        defer { AvatarStorage.delete(named: filename) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: AvatarStorage.url(for: filename).path))
        let loaded = try XCTUnwrap(AvatarStorage.image(named: filename))
        XCTAssertEqual(loaded.size.width, 512, accuracy: 0.5)
        XCTAssertEqual(loaded.size.height, 512, accuracy: 0.5)
    }
}
