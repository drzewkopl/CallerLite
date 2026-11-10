import Foundation

struct SIPAccount: Codable {
    var server: String
    var port: Int
    var username: String
    var password: String
    var displayName: String
    var ownNumber: String
    /// Registrar (host or host:port) for REGISTER and call routing.
    /// Empty = use `server`.
    var registrar: String = ""
}

enum SIPCallEvent: Equatable {
    case ringing
    case connected
    case held
    case resumed
    case muted(Bool)
    case remoteEnded
    case ended
    case transferred
}

/// Events are emitted from arbitrary threads; implementations must hop to the main actor.
protocol SIPClientDelegate: AnyObject {
    func sipClientDidRegister(_ client: any SIPClient)
    func sipClient(_ client: any SIPClient, didFailRegistration reason: String)
    func sipClient(_ client: any SIPClient, didChangeCall callID: UUID, event: SIPCallEvent)
    func sipClient(_ client: any SIPClient, didReceiveIncomingCall callID: UUID, from number: String, displayName: String?)
}

/// Abstraction over a SIP backend.
/// `DemoSIPClient` simulates calls; `RealSIPClient` speaks SIP/UDP + RTP (G.711) natively.
protocol SIPClient: AnyObject {
    var delegate: (any SIPClientDelegate)? { get set }
    var isRegistered: Bool { get }

    func connect(account: SIPAccount)
    func disconnect()

    @discardableResult
    func placeCall(to number: String) -> UUID?
    func answer(callID: UUID)
    func end(callID: UUID)
    func sendDTMF(_ digit: String, callID: UUID)
    func setMuted(_ muted: Bool, callID: UUID)
    func setHeld(_ held: Bool, callID: UUID)
    func transfer(callID: UUID, to number: String)
}
