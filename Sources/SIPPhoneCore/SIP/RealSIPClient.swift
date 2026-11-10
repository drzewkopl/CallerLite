import Foundation

// MARK: - Call leg

final class CallLeg {
    enum Kind { case outbound, inbound }
    enum State { case trying, ringing, confirmed }

    let id: UUID
    let kind: Kind
    var callID: String
    let localTag: String
    var remoteTag: String?
    var localCSeq = 1
    var inviteCSeq = 1
    var state: State = .trying

    /// Full From header value (with our tag) used when we send requests.
    var fromValue = ""
    /// To header value without the remote tag.
    var toValueBase = ""
    var remoteContact: String?
    /// Record-Route values as received; reversed when used as Route set.
    var routeSet: [String] = []

    var lastInviteRequest: SIPRequest?
    var lastProvisional: Data?

    var remoteNumber = ""
    var remoteName: String?

    var offeredPTs: [Int]?
    var sendPT: UInt8 = 0
    var remoteMediaAddress: String?
    var remoteMediaPort: UInt16 = 0
    var authTried = false
    var inviteBranch = ""

    init(kind: Kind) {
        id = UUID()
        self.kind = kind
        callID = RealSIPHelpers.newCallID()
        localTag = RealSIPHelpers.newTag()
    }
}

enum RealSIPHelpers {
    static func randHex(_ n: Int) -> String {
        (0..<n).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined()
    }
    static func newCallID() -> String { randHex(20) }
    static func newTag() -> String { randHex(10) }
    static func newBranch() -> String { "z9hG4bB" + randHex(12) }

    /// Splits "host" / "host:port" (port falls back to `defaultPort`).
    static func splitHostPort(_ spec: String, defaultPort: Int) -> (host: String, port: Int) {
        if let colon = spec.lastIndex(of: ":") {
            let host = String(spec[..<colon])
            let portText = String(spec[spec.index(after: colon)...])
            if !host.isEmpty, let port = Int(portText), (1...65535).contains(port) {
                return (host, port)
            }
        }
        return (spec, defaultPort)
    }
}

// MARK: - Client

/// Native SIP client: REGISTER (digest auth MD5/SHA-256), INVITE dialogs over UDP,
/// G.711 PCMU/PCMA RTP audio, hold (re-INVITE), blind transfer (REFER), DTMF (INFO).
/// All stack state lives on a private serial queue; delegate callbacks may arrive
/// on that queue and are hopped to the main actor by CallManager.
final class RealSIPClient: SIPClient {

    weak var delegate: (any SIPClientDelegate)?

    private let queue = DispatchQueue(label: "sip.stack")

    private var account = SIPAccount(server: "", port: 5060, username: "", password: "", displayName: "", ownNumber: "")

    // Transport
    private var socket: UDPSocket?
    private var localIP = "127.0.0.1"
    private var localSIPPort: UInt16 = 0
    private var serverIP = ""
    private var serverPort: UInt16 = 5060

    // Registrar (next hop for all requests); equals the server when unset.
    private var registrarIP = ""
    private var registrarPort: UInt16 = 5060

    // Registration
    private var registerCallID = ""
    private var registerCSeq = 1
    private var registerTag = ""
    private var regAuthTried = false
    private var regRefreshItem: DispatchWorkItem?
    private var keepaliveItem: DispatchWorkItem?
    private var queueRegistered = false

    // Calls
    private var legs: [UUID: CallLeg] = [:]
    private var legByCallID: [String: UUID] = [:]

    // Media
    private var rtp: RTPSession?
    private var audio: AudioIO?

    // Transactions (retransmissions)
    private var pending: [String: PendingRequest] = [:]

    private final class PendingRequest {
        let data: Data
        let isInvite: Bool
        let onTimeout: (() -> Void)?
        var timer: DispatchWorkItem?
        var attempts = 0
        init(data: Data, isInvite: Bool, onTimeout: (() -> Void)?) {
            self.data = data
            self.isInvite = isInvite
            self.onTimeout = onTimeout
        }
    }

    // MARK: SIPClient (called from the main actor)

    var isRegistered: Bool { queue.sync { queueRegistered } }

    func connect(account newAccount: SIPAccount) {
        queue.async { [weak self] in
            self?.account = newAccount
            self?.start()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.shutdown(unregister: true)
        }
    }

    @discardableResult
    func placeCall(to number: String) -> UUID? {
        queue.sync { internalPlaceCall(number) }
    }

    func answer(callID: UUID) {
        queue.async { self.internalAnswer(callID) }
    }

    func end(callID: UUID) {
        queue.async { self.internalEnd(callID) }
    }

    func sendDTMF(_ digit: String, callID: UUID) {
        queue.async { self.internalDTMF(digit, callID: callID) }
    }

    func setMuted(_ muted: Bool, callID: UUID) {
        queue.async { self.audio?.setMuted(muted) }
    }

    func setHeld(_ held: Bool, callID: UUID) {
        queue.async { self.internalHold(held, callID: callID) }
    }

    func transfer(callID: UUID, to number: String) {
        queue.async { self.internalTransfer(callID, to: number) }
    }

    // MARK: Lifecycle

    private func start() {
        shutdown(unregister: false)

        serverIP = resolveHost(account.server)
        guard !serverIP.isEmpty else {
            failRegistration("Server nicht auflösbar: \(account.server)")
            return
        }
        serverPort = UInt16(max(1, min(65535, account.port)))

        let registrarSpec = account.registrar.trimmingCharacters(in: .whitespacesAndNewlines)
        if registrarSpec.isEmpty {
            registrarIP = serverIP
            registrarPort = serverPort
        } else {
            let (host, port) = RealSIPHelpers.splitHostPort(registrarSpec, defaultPort: Int(serverPort))
            guard let p = UInt16(exactly: port) else {
                failRegistration("Ungültiger Registrar-Port: \(registrarSpec)")
                return
            }
            let ip = resolveHost(host)
            guard !ip.isEmpty else {
                failRegistration("Registrar nicht auflösbar: \(host)")
                return
            }
            registrarIP = ip
            registrarPort = p
        }

        localIP = UDPSocket.primaryLocalIP()
        guard let s = try? UDPSocket() else {
            failRegistration("UDP-Socket konnte nicht geöffnet werden")
            return
        }
        socket = s
        localSIPPort = s.localPort
        s.callbackQueue = queue
        s.onDatagram = { [weak self] data, ip, _ in self?.handleDatagram(data, from: ip) }
        s.startReceiving()

        registerTag = RealSIPHelpers.newTag()
        registerCallID = RealSIPHelpers.newCallID()
        registerCSeq = 1
        regAuthTried = false
        sendRegister()
        startKeepalive()
    }

    private func shutdown(unregister: Bool) {
        regRefreshItem?.cancel(); regRefreshItem = nil
        keepaliveItem?.cancel(); keepaliveItem = nil

        if unregister, socket != nil, queueRegistered {
            sendUnregister()
        }

        for leg in legs.values {
            delegate?.sipClient(self, didChangeCall: leg.id, event: .ended)
        }
        legs.removeAll()
        legByCallID.removeAll()
        stopMedia()

        for p in pending.values { p.timer?.cancel() }
        pending.removeAll()

        socket?.shutdownSocket()
        socket = nil
        queueRegistered = false
    }

    private func failRegistration(_ reason: String) {
        queueRegistered = false
        delegate?.sipClient(self, didFailRegistration: reason)
    }

    // MARK: Registration

    private func hostPortStr() -> String {
        account.port == 5060 ? account.server : "\(account.server):\(account.port)"
    }

    private func sendRegister(authHeader: (String, String)? = nil) {
        guard let s = socket else { return }
        let hostPort = hostPortStr()
        let display = account.displayName.isEmpty ? account.username : account.displayName
        let fromValue = "\"\(display)\" <sip:\(account.username)@\(hostPort)>"

        let branch = RealSIPHelpers.newBranch()
        var h: [(String, String)] = [
            ("Via", "SIP/2.0/UDP \(localIP):\(localSIPPort);rport;branch=\(branch)"),
            ("Max-Forwards", "70"),
            ("From", "\(fromValue);tag=\(registerTag)"),
            ("To", fromValue),
            ("Call-ID", registerCallID),
            ("CSeq", "\(registerCSeq) REGISTER"),
            ("Contact", "<sip:\(account.username)@\(localIP):\(localSIPPort)>"),
            ("Expires", "300"),
            ("Allow", "INVITE, ACK, CANCEL, BYE, REFER, OPTIONS, INFO, NOTIFY"),
        ]
        if let a = authHeader { h.append(a) }

        let req = SIPRequest(method: "REGISTER", requestURI: "sip:\(hostPort)", headers: h, body: nil)
        sendTracked(req, branch: branch, invite: false) { [weak self] in
            self?.failRegistration("Keine Antwort vom Server (Timeout)")
        }
        _ = s
    }

    private func sendUnregister() {
        guard let s = socket else { return }
        let hostPort = hostPortStr()
        let display = account.displayName.isEmpty ? account.username : account.displayName
        let fromValue = "\"\(display)\" <sip:\(account.username)@\(hostPort)>"
        let h: [(String, String)] = [
            ("Via", "SIP/2.0/UDP \(localIP):\(localSIPPort);rport;branch=\(RealSIPHelpers.newBranch())"),
            ("Max-Forwards", "70"),
            ("From", "\(fromValue);tag=\(registerTag)"),
            ("To", fromValue),
            ("Call-ID", registerCallID),
            ("CSeq", "\(registerCSeq + 1) REGISTER"),
            ("Contact", "<sip:\(account.username)@\(localIP):\(localSIPPort)>"),
            ("Expires", "0"),
        ]
        let req = SIPRequest(method: "REGISTER", requestURI: "sip:\(hostPort)", headers: h, body: nil)
        s.send(Data(SIPWire.serializeRequest(req).utf8), to: registrarIP, port: registrarPort)
    }

    private func handleRegisterResponse(_ resp: SIPResponse) {
        switch resp.statusCode {
        case 200:
            queueRegistered = true
            regAuthTried = false
            let expires = Int(resp.header("Expires")
                ?? resp.headerValues("Contact").first.flatMap { extractParam($0, "expires") }
                ?? "300") ?? 300
            scheduleRegisterRefresh(max(60, min(expires - 30, 300)))
            delegate?.sipClientDidRegister(self)

        case 401, 407:
            guard !regAuthTried else {
                failRegistration("Anmeldung fehlgeschlagen (Benutzer/Passwort?)")
                return
            }
            regAuthTried = true
            let headerName = resp.statusCode == 401 ? "WWW-Authenticate" : "Proxy-Authenticate"
            guard let value = resp.header(headerName), let challenge = DigestChallenge.parse(value) else {
                failRegistration("Ungültige Authentifizierungs-Anforderung")
                return
            }
            registerCSeq += 1
            let auth = DigestAuth.authorize(
                username: account.username,
                password: account.password,
                method: "REGISTER",
                uri: "sip:\(hostPortStr())",
                challenge: challenge,
                cnonce: RealSIPHelpers.randHex(16),
                nc: "00000001",
                proxy: resp.statusCode == 407
            )
            sendRegister(authHeader: (resp.statusCode == 401 ? "Authorization" : "Proxy-Authorization", auth))

        case 403:
            failRegistration("Anmeldung abgelehnt (403)")
        case let code where code >= 400:
            failRegistration("Registrierung fehlgeschlagen (\(code))")
        default:
            break
        }
    }

    private func scheduleRegisterRefresh(_ seconds: Int) {
        regRefreshItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.registerCSeq += 1
            self.regAuthTried = false
            self.sendRegister()
        }
        regRefreshItem = item
        queue.asyncAfter(deadline: .now() + Double(seconds), execute: item)
    }

    private func startKeepalive() {
        keepaliveItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let s = self.socket else { return }
            s.send(Data("\r\n\r\n".utf8), to: self.registrarIP, port: self.registrarPort)
            self.startKeepalive()
        }
        keepaliveItem = item
        queue.asyncAfter(deadline: .now() + 25, execute: item)
    }

    // MARK: Outbound calls

    private func internalPlaceCall(_ number: String) -> UUID? {
        guard socket != nil, queueRegistered, legs.isEmpty else { return nil }
        guard let session = RTPSession() else { return nil }
        rtp = session

        let leg = CallLeg(kind: .outbound)
        let target = SIPURIHelpers.normalizeTarget(number, server: hostPortStr())
        leg.remoteNumber = SIPURIHelpers.userPart(of: target)
        let display = account.displayName.isEmpty ? account.username : account.displayName
        leg.fromValue = "\"\(display)\" <sip:\(account.username)@\(hostPortStr())>;tag=\(leg.localTag)"
        leg.toValueBase = "<\(target)>"
        leg.inviteCSeq = leg.localCSeq

        let offer = SDP.offer(localIP: localIP, rtpPort: session.localPort, sessionID: Int.random(in: 100_000_000...999_999_999))
        let req = inDialogRequest(leg, method: "INVITE", body: offer, contentType: "application/sdp",
                                  cseq: leg.localCSeq, uriOverride: target)
        leg.lastInviteRequest = req
        leg.inviteBranch = req.topViaBranch ?? ""

        legs[leg.id] = leg
        legByCallID[leg.callID] = leg.id

        sendTracked(req, branch: leg.inviteBranch, invite: true) { [weak self, legID = leg.id] in
            guard let self, self.legs[legID] != nil else { return }
            self.internalEnd(legID) // CANCEL so the callee stops ringing
        }
        return leg.id
    }

    // MARK: Inbound calls

    private func internalAnswer(_ callID: UUID) {
        guard let leg = legs[callID], leg.kind == .inbound, leg.state == .ringing,
              let offered = leg.offeredPTs, let chosen = SDP.chooseCodec(offered: offered) else { return }

        if rtp == nil { rtp = RTPSession() }
        guard let rtpSession = rtp, let inviteReq = leg.lastInviteRequest else { return }

        leg.sendPT = UInt8(chosen)
        let answer = SDP.answer(localIP: localIP, rtpPort: rtpSession.localPort, chosenPT: chosen,
                                includeTelephoneEvent: offered.contains(101),
                                sessionID: Int.random(in: 100_000_000...999_999_999))

        send(buildResponse(to: inviteReq, status: 200, reason: "OK", body: answer,
                           contentType: "application/sdp", localTag: leg.localTag))
        leg.state = .confirmed
        notifyEvent(.connected, for: leg.id)
        startMedia(for: leg)
    }

    // MARK: Ending / hold / transfer / DTMF

    private func internalEnd(_ callID: UUID) {
        guard let leg = legs[callID] else { return }
        switch (leg.kind, leg.state) {
        case (.outbound, .trying), (.outbound, .ringing):
            let cancel = buildCancel(leg)
            send(Data(SIPWire.serializeRequest(cancel).utf8))
            terminateLeg(leg, event: .ended)
        case (.inbound, .ringing):
            if let inviteReq = leg.lastInviteRequest {
                send(buildResponse(to: inviteReq, status: 486, reason: "Busy Here", localTag: leg.localTag))
            }
            terminateLeg(leg, event: .ended)
        case (_, .confirmed):
            let bye = inDialogRequest(leg, method: "BYE")
            send(Data(SIPWire.serializeRequest(bye).utf8))
            terminateLeg(leg, event: .ended)
        default:
            terminateLeg(leg, event: .ended)
        }
    }

    private func internalHold(_ held: Bool, callID: UUID) {
        guard let leg = legs[callID], leg.state == .confirmed, let rtpSession = rtp else { return }
        audio?.setMuted(held) // send nothing while held
        let offer = SDP.offer(localIP: localIP, rtpPort: rtpSession.localPort,
                              sessionID: Int.random(in: 100_000_000...999_999_999), hold: held)
        let req = inDialogRequest(leg, method: "INVITE", body: offer, contentType: "application/sdp")
        send(Data(SIPWire.serializeRequest(req).utf8))
    }

    private func internalTransfer(_ callID: UUID, to number: String) {
        guard let leg = legs[callID], leg.state == .confirmed else { return }
        let target = SIPURIHelpers.normalizeTarget(number, server: hostPortStr())
        let req = inDialogRequest(leg, method: "REFER", extraHeaders: [("Refer-To", "<\(target)>")])
        send(Data(SIPWire.serializeRequest(req).utf8))
    }

    private func internalDTMF(_ digit: String, callID: UUID) {
        guard let leg = legs[callID], leg.state == .confirmed, !digit.isEmpty else { return }
        let body = "Signal=\(digit)\r\nDuration=160\r\n"
        let req = inDialogRequest(leg, method: "INFO", body: body, contentType: "application/dtmf-relay")
        send(Data(SIPWire.serializeRequest(req).utf8))
    }

    // MARK: Datagram dispatch

    private func handleDatagram(_ data: Data, from ip: String) {
        guard ip == registrarIP || ip == serverIP, let msg = SIPParser.parse(data) else { return }
        switch msg {
        case .response(let resp): handleResponse(resp)
        case .request(let req): handleRequest(req)
        }
    }

    // MARK: Responses

    private func handleResponse(_ resp: SIPResponse) {
        if let branch = resp.topViaBranch, let p = pending[branch] {
            // "100 Trying" does not stop INVITE retransmission (RFC 3261 §14.1);
            // 180+ and final responses do.
            let stopRetransmit = !(p.isInvite && resp.statusCode == 100)
            if stopRetransmit {
                p.timer?.cancel()
                pending[branch] = nil
            }
        }

        guard let callID = resp.callID else { return }

        if callID == registerCallID, resp.cseqMethod == "REGISTER" {
            handleRegisterResponse(resp)
            return
        }

        guard let legID = legByCallID[callID], let leg = legs[legID] else {
            // Orphaned final response (e.g. 487 after our CANCEL): best-effort ACK.
            if resp.cseqMethod == "INVITE", resp.statusCode >= 300 {
                sendAckFromResponse(resp)
            }
            return
        }

        switch (resp.cseqMethod ?? "", resp.statusCode) {
        case ("INVITE", let code) where code < 200:
            if code >= 180, leg.state == .trying {
                leg.state = .ringing
                notifyEvent(.ringing, for: leg.id)
            }

        case ("INVITE", 200):
            leg.remoteTag = resp.toTag ?? leg.remoteTag
            leg.remoteContact = resp.header("Contact").map(angleStrip)
            leg.routeSet = resp.headerValues("Record-Route")
            sendAck(leg: leg, resp: resp)
            if leg.state != .confirmed {
                if let body = resp.body, let media = SDP.parse(body) {
                    leg.remoteMediaAddress = media.address
                    leg.remoteMediaPort = media.port
                    leg.sendPT = SDP.chooseCodec(offered: media.payloadTypes).map { UInt8($0) } ?? leg.sendPT
                }
                leg.state = .confirmed
                notifyEvent(.connected, for: leg.id)
                startMedia(for: leg)
            } else {
                updateRemoteMedia(leg, body: resp.body)
            }

        case ("INVITE", let code) where code >= 300:
            // Servers retransmit a final response until a matching ACK arrives;
            // stale retransmissions (older CSeq) must not tear down the call.
            if let cseq = resp.cseqNumber, cseq != leg.inviteCSeq {
                sendAck(leg: leg, resp: resp)
                return
            }
            if code == 401 || code == 407 {
                sendAck(leg: leg, resp: resp)
                if !leg.authTried, leg.state != .confirmed {
                    leg.authTried = true
                    retryInviteWithAuth(leg, resp: resp)
                } else {
                    terminateLeg(leg, event: .ended) // auth for current INVITE rejected
                }
                return
            }
            sendAck(leg: leg, resp: resp)
            terminateLeg(leg, event: .ended)

        case ("BYE", _):
            terminateLeg(leg, event: nil)

        case ("REFER", let code) where (200..<300).contains(code):
            let bye = inDialogRequest(leg, method: "BYE")
            send(Data(SIPWire.serializeRequest(bye).utf8))
            terminateLeg(leg, event: .transferred)

        default:
            break
        }
    }

    private func retryInviteWithAuth(_ leg: CallLeg, resp: SIPResponse) {
        let headerName = resp.statusCode == 401 ? "WWW-Authenticate" : "Proxy-Authenticate"
        guard let value = resp.header(headerName), let challenge = DigestChallenge.parse(value) else {
            terminateLeg(leg, event: .ended)
            return
        }
        leg.localCSeq += 1
        leg.inviteCSeq = leg.localCSeq
        let body = leg.lastInviteRequest?.body
        let uri = leg.lastInviteRequest?.requestURI ?? "sip:\(leg.remoteNumber)@\(hostPortStr())"
        var req = inDialogRequest(leg, method: "INVITE", body: body, contentType: "application/sdp",
                                  cseq: leg.localCSeq, uriOverride: uri)
        let auth = DigestAuth.authorize(
            username: account.username,
            password: account.password,
            method: "INVITE",
            uri: uri,
            challenge: challenge,
            cnonce: RealSIPHelpers.randHex(16),
            nc: "00000001",
            proxy: resp.statusCode == 407
        )
        req.headers.append((resp.statusCode == 401 ? "Authorization" : "Proxy-Authorization", auth))
        leg.lastInviteRequest = req
        leg.inviteBranch = req.topViaBranch ?? ""

        sendTracked(req, branch: leg.inviteBranch, invite: true) { [weak self, legID = leg.id] in
            guard let self, self.legs[legID] != nil else { return }
            self.internalEnd(legID) // CANCEL so the callee stops ringing
        }
    }

    // MARK: Requests from the server

    private func handleRequest(_ req: SIPRequest) {
        switch req.method {
        case "INVITE":
            handleInvite(req)

        case "ACK":
            break // dialog confirmed; nothing to do

        case "BYE":
            if let cid = req.callID, let id = legByCallID[cid], let leg = legs[id] {
                send(buildResponse(to: req, status: 200, reason: "OK"))
                terminateLeg(leg, event: .remoteEnded)
            } else {
                send(buildResponse(to: req, status: 481, reason: "Call/Transaction Does Not Exist"))
            }

        case "CANCEL":
            handleCancel(req)

        case "OPTIONS":
            send(buildResponse(to: req, status: 200, reason: "OK",
                               extraHeaders: [("Allow", "INVITE, ACK, CANCEL, BYE, REFER, OPTIONS, INFO, NOTIFY")]))

        case "INFO", "NOTIFY", "MESSAGE", "UPDATE", "REFER", "SUBSCRIBE":
            if req.callID != nil, legByCallID[req.callID!] != nil {
                send(buildResponse(to: req, status: 200, reason: "OK"))
            } else {
                send(buildResponse(to: req, status: 481, reason: "Call/Transaction Does Not Exist"))
            }

        default:
            send(buildResponse(to: req, status: 405, reason: "Method Not Allowed"))
        }
    }

    private func handleInvite(_ req: SIPRequest) {
        guard let cid = req.callID else { return }

        // Retransmitted INVITE: resend the last provisional response.
        if let id = legByCallID[cid], let leg = legs[id] {
            if leg.kind == .inbound, req.topViaBranch == leg.inviteBranch {
                if let p = leg.lastProvisional { send(p) }
                return
            }
            // Re-INVITE within a confirmed dialog: accept, keep current media.
            if leg.state == .confirmed, let offered = req.body.flatMap(SDP.parse) {
                let chosen = SDP.chooseCodec(offered: offered.payloadTypes) ?? Int(leg.sendPT)
                let answer = SDP.answer(localIP: localIP, rtpPort: rtp?.localPort ?? 0, chosenPT: chosen,
                                        includeTelephoneEvent: offered.payloadTypes.contains(101),
                                        sessionID: Int.random(in: 100_000_000...999_999_999))
                send(buildResponse(to: req, status: 200, reason: "OK", body: answer,
                                   contentType: "application/sdp", localTag: leg.localTag))
                if offered.address != "0.0.0.0", offered.port > 0 {
                    leg.remoteMediaAddress = offered.address
                    leg.remoteMediaPort = offered.port
                    rtp?.setRemote(ip: offered.address, port: offered.port)
                }
            } else {
                send(buildResponse(to: req, status: 488, reason: "Not Acceptable Here", localTag: leg.localTag))
            }
            return
        }

        // New inbound call: refuse when busy or unregistered.
        if !legs.isEmpty || !queueRegistered {
            send(buildResponse(to: req, status: 486, reason: "Busy Here", localTag: RealSIPHelpers.newTag()))
            return
        }

        guard let offer = req.body, let media = SDP.parse(offer),
              SDP.chooseCodec(offered: media.payloadTypes) != nil else {
            send(buildResponse(to: req, status: 488, reason: "Not Acceptable Here", localTag: RealSIPHelpers.newTag()))
            return
        }

        let leg = CallLeg(kind: .inbound)
        leg.callID = cid
        leg.remoteTag = req.fromTag
        leg.fromValue = (req.header("To") ?? "<sip:\(account.username)@\(hostPortStr())>") + ";tag=\(leg.localTag)"
        leg.toValueBase = req.header("From") ?? ""
        leg.remoteContact = req.header("Contact").map(angleStrip)
        leg.routeSet = req.headerValues("Record-Route")
        leg.remoteName = req.header("From").flatMap { SIPURIHelpers.displayName(of: $0) }
        leg.remoteNumber = req.header("From").map { SIPURIHelpers.userPart(of: $0) } ?? ""
        leg.remoteMediaAddress = media.address
        leg.remoteMediaPort = media.port
        leg.offeredPTs = media.payloadTypes
        leg.lastInviteRequest = req
        leg.inviteBranch = req.topViaBranch ?? ""
        leg.state = .ringing

        legs[leg.id] = leg
        legByCallID[cid] = leg.id

        send(buildResponse(to: req, status: 100, reason: "Trying", localTag: leg.localTag))
        let ringing = buildResponse(to: req, status: 180, reason: "Ringing", localTag: leg.localTag)
        leg.lastProvisional = ringing
        send(ringing)

        delegate?.sipClient(self, didReceiveIncomingCall: leg.id, from: leg.remoteNumber, displayName: leg.remoteName)
    }

    private func handleCancel(_ req: SIPRequest) {
        guard let cid = req.callID, let id = legByCallID[cid], let leg = legs[id],
              leg.kind == .inbound, leg.state == .ringing else {
            send(buildResponse(to: req, status: 481, reason: "Call/Transaction Does Not Exist"))
            return
        }
        send(buildResponse(to: req, status: 200, reason: "OK")) // to the CANCEL
        if let inviteReq = leg.lastInviteRequest {
            send(buildResponse(to: inviteReq, status: 487, reason: "Request Terminated", localTag: leg.localTag))
        }
        terminateLeg(leg, event: .remoteEnded)
    }

    // MARK: Message builders

    private func send(_ data: Data) {
        socket?.send(data, to: registrarIP, port: registrarPort)
    }

    private func sendTracked(_ req: SIPRequest, branch: String, invite: Bool, _ onTimeout: @escaping () -> Void) {
        let data = Data(SIPWire.serializeRequest(req).utf8)
        let p = PendingRequest(data: data, isInvite: invite, onTimeout: onTimeout)
        pending[branch] = p
        send(data)
        scheduleRetransmit(branch)
    }

    private func scheduleRetransmit(_ branch: String) {
        guard let p = pending[branch] else { return }
        let delay = p.attempts == 0 ? 0.5 : min(4.0, 0.5 * pow(2, Double(p.attempts)))
        p.attempts += 1

        let item = DispatchWorkItem { [weak self] in
            guard let self, let p = self.pending[branch] else { return }
            if p.attempts >= 7 {
                self.pending[branch] = nil
                p.onTimeout?()
                return
            }
            self.send(p.data)
            self.scheduleRetransmit(branch)
        }
        p.timer = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// In-dialog request (INVITE/ACK/BYE/INFO/REFER…) built from leg state.
    private func inDialogRequest(_ leg: CallLeg,
                                 method: String,
                                 body: String? = nil,
                                 contentType: String? = nil,
                                 extraHeaders: [(String, String)] = [],
                                 cseq: Int? = nil,
                                 uriOverride: String? = nil) -> SIPRequest {
        let uri = uriOverride ?? leg.remoteContact ?? "sip:\(leg.remoteNumber)@\(hostPortStr())"

        var h: [(String, String)] = [
            ("Via", "SIP/2.0/UDP \(localIP):\(localSIPPort);rport;branch=\(RealSIPHelpers.newBranch())"),
            ("Max-Forwards", "70"),
            ("From", leg.fromValue),
        ]
        var to = leg.toValueBase
        if let t = leg.remoteTag { to += ";tag=\(t)" }
        h.append(("To", to))
        h.append(("Call-ID", leg.callID))
        let c: Int
        if let cseq { c = cseq } else { leg.localCSeq += 1; c = leg.localCSeq }
        h.append(("CSeq", "\(c) \(method)"))
        h.append(("Contact", "<sip:\(account.username)@\(localIP):\(localSIPPort)>"))
        h.append(("Allow", "INVITE, ACK, CANCEL, BYE, REFER, OPTIONS, INFO, NOTIFY"))
        if !leg.routeSet.isEmpty {
            for r in leg.routeSet.reversed() { h.append(("Route", r)) }
        }
        h.append(contentsOf: extraHeaders)
        if let ct = contentType { h.append(("Content-Type", ct)) }

        return SIPRequest(method: method, requestURI: uri, headers: h, body: body)
    }

    /// ACK for a final/provisional response of our INVITE.
    private func sendAck(leg: CallLeg, resp: SIPResponse) {
        // ACK for a non-2xx final response belongs to the INVITE transaction
        // (RFC 3261 §17.1.1.3): same Via branch and same Request-URI.
        let isNon2xx = resp.statusCode >= 300
        let uri: String
        if isNon2xx {
            uri = leg.lastInviteRequest?.requestURI
                ?? (resp.header("To").map(angleStrip) ?? "sip:\(account.username)@\(hostPortStr())")
        } else {
            uri = leg.remoteContact
                ?? (resp.header("To").map(angleStrip) ?? "sip:\(account.username)@\(hostPortStr())")
        }
        let branch = isNon2xx
            ? (resp.topViaBranch ?? leg.inviteBranch)
            : RealSIPHelpers.newBranch()
        var h: [(String, String)] = [
            ("Via", "SIP/2.0/UDP \(localIP):\(localSIPPort);rport;branch=\(branch)"),
            ("Max-Forwards", "70"),
            ("From", resp.header("From") ?? leg.fromValue),
        ]
        if let to = resp.header("To") { h.append(("To", to)) }
        if let cid = resp.callID { h.append(("Call-ID", cid)) }
        h.append(("CSeq", "\(resp.cseqNumber ?? leg.inviteCSeq) ACK"))
        for r in leg.routeSet.reversed() { h.append(("Route", r)) }

        let req = SIPRequest(method: "ACK", requestURI: uri, headers: h, body: nil)
        send(Data(SIPWire.serializeRequest(req).utf8))
    }

    /// Best-effort ACK built purely from a response (dialog already torn down).
    private func sendAckFromResponse(_ resp: SIPResponse) {
        let uri = resp.header("To").map(angleStrip) ?? "sip:\(account.username)@\(hostPortStr())"
        var h: [(String, String)] = [
            ("Via", "SIP/2.0/UDP \(localIP):\(localSIPPort);rport;branch=\(RealSIPHelpers.newBranch())"),
            ("Max-Forwards", "70"),
        ]
        if let f = resp.header("From") { h.append(("From", f)) }
        if let t = resp.header("To") { h.append(("To", t)) }
        if let cid = resp.callID { h.append(("Call-ID", cid)) }
        h.append(("CSeq", "\(resp.cseqNumber ?? 1) ACK"))
        let req = SIPRequest(method: "ACK", requestURI: uri, headers: h, body: nil)
        send(Data(SIPWire.serializeRequest(req).utf8))
    }

    /// CANCEL for an outgoing INVITE: must reuse the INVITE's Via branch.
    private func buildCancel(_ leg: CallLeg) -> SIPRequest {
        guard let inv = leg.lastInviteRequest else {
            return SIPRequest(method: "CANCEL", requestURI: "sip:\(account.server)", headers: [], body: nil)
        }
        var h: [(String, String)] = []
        if let via = inv.header("Via") { h.append(("Via", via)) }
        if let mf = inv.header("Max-Forwards") { h.append(("Max-Forwards", mf)) }
        if let f = inv.header("From") { h.append(("From", f)) }
        if let t = inv.header("To") { h.append(("To", t)) }
        if let cid = inv.callID { h.append(("Call-ID", cid)) }
        h.append(("CSeq", "\(inv.cseqNumber ?? 1) CANCEL"))
        if let ct = inv.header("Contact") { h.append(("Contact", ct)) }
        for r in leg.routeSet.reversed() { h.append(("Route", r)) }
        return SIPRequest(method: "CANCEL", requestURI: inv.requestURI, headers: h, body: nil)
    }

    /// UAS response echoing Via/From/To/Call-ID/CSeq of the received request.
    private func buildResponse(to req: SIPRequest,
                               status: Int,
                               reason: String,
                               body: String? = nil,
                               contentType: String? = nil,
                               extraHeaders: [(String, String)] = [],
                               localTag: String? = nil) -> Data {
        var h: [(String, String)] = []
        for v in req.headerValues("Via") { h.append(("Via", v)) }
        for rr in req.headerValues("Record-Route") { h.append(("Record-Route", rr)) }
        if let f = req.header("From") { h.append(("From", f)) }
        var to = req.header("To") ?? ""
        if extractParam(to, "tag") == nil, let tag = localTag {
            to += ";tag=\(tag)"
        }
        h.append(("To", to))
        if let cid = req.callID { h.append(("Call-ID", cid)) }
        if let cs = req.header("CSeq") { h.append(("CSeq", cs)) }
        if localTag != nil {
            h.append(("Contact", "<sip:\(account.username)@\(localIP):\(localSIPPort)>"))
        }
        h.append(contentsOf: extraHeaders)
        if let ct = contentType { h.append(("Content-Type", ct)) }

        let resp = SIPResponse(statusCode: status, reason: reason, headers: h, body: body)
        return Data(SIPWire.serializeResponse(resp).utf8)
    }

    // MARK: Media

    private func startMedia(for leg: CallLeg) {
        guard let rtpSession = rtp else { return }
        rtpSession.sendPT = leg.sendPT
        if let addr = leg.remoteMediaAddress, leg.remoteMediaPort > 0, addr != "0.0.0.0" {
            rtpSession.setRemote(ip: addr, port: leg.remoteMediaPort)
        }
        if audio == nil { audio = AudioIO() }
        audio?.onSendAudio = { [weak self] samples in
            self?.rtp?.sendAudio(samples: samples)
        }
        rtpSession.onAudio = { [weak self] pt, payload in
            self?.audio?.play(pt: pt, payload: payload)
        }
        audio?.start()
    }

    private func updateRemoteMedia(_ leg: CallLeg, body: String?) {
        guard let body, let media = SDP.parse(body),
              media.address != "0.0.0.0", media.port > 0 else { return }
        leg.remoteMediaAddress = media.address
        leg.remoteMediaPort = media.port
        rtp?.setRemote(ip: media.address, port: media.port)
    }

    // MARK: Leg lifecycle

    private func terminateLeg(_ leg: CallLeg, event: SIPCallEvent?) {
        if let e = event { notifyEvent(e, for: leg.id) }
        legs[leg.id] = nil
        legByCallID[leg.callID] = nil
        if legs.isEmpty { stopMedia() }
    }

    private func stopMedia() {
        rtp?.close()
        rtp = nil
        audio?.stop()
        audio = nil
    }

    private func notifyEvent(_ event: SIPCallEvent, for id: UUID) {
        delegate?.sipClient(self, didChangeCall: id, event: event)
    }

    // MARK: DNS

    private func resolveHost(_ host: String) -> String {
        var inAddr = in_addr()
        if inet_pton(AF_INET, host, &inAddr) == 1 {
            return host
        }
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result?.pointee.ai_addr else { return "" }
        defer { freeaddrinfo(result) }

        let addrPtr = first.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0 }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var inA = addrPtr.pointee.sin_addr
        inet_ntop(AF_INET, &inA, &buf, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buf)
    }
}
