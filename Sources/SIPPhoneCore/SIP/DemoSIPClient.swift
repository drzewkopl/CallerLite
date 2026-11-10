import Foundation

/// Simulated SIP backend: outgoing calls start "ringing" after ~0.7s and
/// connect after ~2.1s; incoming calls ring for 14s and then count as missed.
final class DemoSIPClient: SIPClient {
    weak var delegate: (any SIPClientDelegate)?
    private(set) var isRegistered = false

    /// Call IDs that are still "alive"; queued events for dead calls are dropped.
    private var alive: Set<UUID> = []

    func connect(account: SIPAccount) {
        isRegistered = true
        delegate?.sipClientDidRegister(self)
    }

    func disconnect() {
        isRegistered = false
        alive.removeAll()
    }

    @discardableResult
    func placeCall(to number: String) -> UUID? {
        let id = UUID()
        alive.insert(id)
        deliver(.ringing, for: id, after: 0.7, ifAlive: true)
        deliver(.connected, for: id, after: 2.1, ifAlive: true)
        return id
    }

    func answer(callID: UUID) {
        deliver(.connected, for: callID, after: 0.35, ifAlive: true)
    }

    func end(callID: UUID) {
        alive.remove(callID)
        deliver(.ended, for: callID, after: 0, ifAlive: false)
    }

    func sendDTMF(_ digit: String, callID: UUID) {}

    func setMuted(_ muted: Bool, callID: UUID) {}

    func setHeld(_ held: Bool, callID: UUID) {}

    func transfer(callID: UUID, to number: String) {
        alive.remove(callID)
        deliver(.transferred, for: callID, after: 0.6, ifAlive: false)
    }

    // MARK: Demo-only

    func simulateIncomingCall(number: String, displayName: String?) {
        let id = UUID()
        alive.insert(id)
        delegate?.sipClient(self, didReceiveIncomingCall: id, from: number, displayName: displayName)
        deliver(.remoteEnded, for: id, after: 14, ifAlive: true)
    }

    // MARK: Delivery

    private func deliver(_ event: SIPCallEvent, for id: UUID, after delay: TimeInterval, ifAlive: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, ifAlive ? self.alive.contains(id) : true else { return }
            self.delegate?.sipClient(self, didChangeCall: id, event: event)
        }
    }
}
