import Foundation
import Combine

enum RegistrationStatus {
    case demo
    case connecting
    case registered
    case failed(String)
}

@MainActor
public final class CallManager: ObservableObject, SIPClientDelegate {

    public struct ActiveCall: Identifiable {
        public enum Phase { case dialing, ringing, incoming, active, held }
        public let id: UUID
        public let direction: CallDirection
        public var contact: Contact?
        public var displayName: String
        public var company: String?
        public let number: String
        public var phase: Phase
        public var startedAt: Date?
        public var isMuted: Bool = false
    }

    // MARK: Published state

    @Published private(set) var activeCall: ActiveCall?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var history: [CallRecord] = []
    @Published private(set) var callbackList: [CallbackEntry] = []
    @Published private(set) var handledMissedIDs: Set<UUID> = []
    @Published private(set) var registration: RegistrationStatus = .demo
    @Published private(set) var availability: Availability = .available

    // MARK: SIP

    private(set) var sip: any SIPClient
    var contactLookup: ((String) -> Contact?)?

    private var timerCancellable: AnyCancellable?
    private let store = JSONStore(name: "SIPPhone")

    // MARK: Init

    public init() {
        if let saved = store.load([CallRecord].self, from: "history.json") {
            history = saved
        }
        if let saved = store.load([CallbackEntry].self, from: "callbacks.json") {
            callbackList = saved
        }
        if let saved = store.load([UUID].self, from: "handled.json") {
            handledMissedIDs = Set(saved)
        }
        if let raw = UserDefaults.standard.string(forKey: "sip.availability"),
           let saved = Availability(rawValue: raw) {
            availability = saved
        }

        sip = DemoSIPClient()
        sip.delegate = self
    }

    public var canSimulateIncoming: Bool { sip is DemoSIPClient }

    /// Swaps the SIP backend (demo <-> real) and connects with the given account.
    func swapClient(to client: any SIPClient, account: SIPAccount) {
        sip.delegate = nil
        sip.disconnect()
        sip = client
        sip.delegate = self
        registration = client is DemoSIPClient ? .demo : .connecting
        client.connect(account: account)
    }

    // MARK: Derived

    var missedRecords: [CallRecord] {
        history.filter { $0.wasMissed && !handledMissedIDs.contains($0.id) }
    }

    var missedTodayCount: Int {
        missedRecords.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    // MARK: Placing calls

    func placeCall(_ contact: Contact) {
        placeCall(
            number: contact.number,
            displayName: contact.displayName,
            company: contact.company,
            contact: contact
        )
    }

    func placeCall(number: String, displayName: String? = nil, company: String? = nil, contact: Contact? = nil) {
        guard activeCall == nil else { return }
        let id = sip.placeCall(to: number) ?? UUID()
        activeCall = ActiveCall(
            id: id,
            direction: .outgoing,
            contact: contact,
            displayName: displayName ?? number,
            company: company,
            number: number,
            phase: .dialing
        )
        elapsed = 0
    }

    func requestIncoming(from contact: Contact) {
        guard activeCall == nil,
              let demo = sip as? DemoSIPClient else { return }
        demo.simulateIncomingCall(number: contact.number, displayName: contact.displayName)
    }

    func answerIncoming() {
        guard let call = activeCall else { return }
        sip.answer(callID: call.id)
    }

    public func endActiveCall() {
        guard let call = activeCall else { return }
        sip.end(callID: call.id)
        // Always return to the main screen immediately: a backend without a
        // matching call leg (e.g. failed registration) emits no `.ended` event.
        finalize(transferred: false)
    }

    func toggleMute() {
        guard var call = activeCall, call.phase == .active || call.phase == .held else { return }
        call.isMuted.toggle()
        activeCall = call
        sip.setMuted(call.isMuted, callID: call.id)
    }

    func toggleHold() {
        guard var call = activeCall, call.phase == .active || call.phase == .held else { return }
        let hold = call.phase == .active
        call.phase = hold ? .held : .active
        activeCall = call
        sip.setHeld(hold, callID: call.id)
    }

    func sendDTMF(_ digit: String) {
        guard let call = activeCall else { return }
        sip.sendDTMF(digit, callID: call.id)
    }

    func transferCall(to contact: Contact) {
        guard let call = activeCall else { return }
        sip.transfer(callID: call.id, to: contact.number)
    }

    // MARK: Availability

    func setAvailability(_ status: Availability) {
        availability = status
        UserDefaults.standard.set(status.rawValue, forKey: "sip.availability")
    }

    // MARK: Missed / callback bookkeeping

    func markHandled(_ recordID: UUID) {
        handledMissedIDs.insert(recordID)
        persist()
    }

    func addToCallbacks(_ record: CallRecord) {
        callbackList.removeAll { normalizedNumber($0.number) == normalizedNumber(record.number) }
        callbackList.insert(
            CallbackEntry(
                contactID: record.contactID,
                displayName: record.displayName,
                company: record.company,
                number: record.number
            ),
            at: 0
        )
        markHandled(record.id)
    }

    func removeFromCallbacks(_ entry: CallbackEntry) {
        callbackList.removeAll { $0.id == entry.id }
        persist()
    }

    func clearCallbacks(forNumber number: String) {
        callbackList.removeAll { normalizedNumber($0.number) == normalizedNumber(number) }
        persist()
    }

    func deleteRecord(_ id: UUID) {
        history.removeAll { $0.id == id }
        persist()
    }

    // MARK: SIPClientDelegate (nonisolated hoppers -> main actor)

    nonisolated func sipClientDidRegister(_ client: any SIPClient) {
        Task { @MainActor in
            if !(self.sip is DemoSIPClient) {
                self.registration = .registered
            }
        }
    }

    nonisolated func sipClient(_ client: any SIPClient, didFailRegistration reason: String) {
        Task { @MainActor in
            self.registration = .failed(reason)
        }
    }

    nonisolated func sipClient(_ client: any SIPClient,
                               didReceiveIncomingCall callID: UUID,
                               from number: String,
                               displayName: String?) {
        Task { @MainActor in
            self.handleIncomingCall(callID: callID, number: number, displayName: displayName)
        }
    }

    nonisolated func sipClient(_ client: any SIPClient, didChangeCall callID: UUID, event: SIPCallEvent) {
        Task { @MainActor in
            self.handleCallEvent(callID: callID, event: event)
        }
    }

    // MARK: Event handling (main actor)

    private func handleIncomingCall(callID: UUID, number: String, displayName: String?) {
        // "Beschäftigt"/"Nicht stören": reject silently and note the missed call.
        guard availability.acceptsCalls else {
            sip.end(callID: callID)
            let contact = contactLookup?(number)
            appendRecord(CallRecord(
                contactID: contact?.id,
                displayName: displayName ?? contact?.displayName ?? number,
                company: contact?.company,
                number: number,
                direction: .incoming,
                date: Date(),
                duration: 0,
                wasAnswered: false
            ))
            return
        }
        guard activeCall == nil else {
            sip.end(callID: callID) // busy: reject
            return
        }
        let contact = contactLookup?(number)
        activeCall = ActiveCall(
            id: callID,
            direction: .incoming,
            contact: contact,
            displayName: displayName ?? contact?.displayName ?? number,
            company: contact?.company,
            number: number,
            phase: .incoming
        )
        elapsed = 0
    }

    private func handleCallEvent(callID: UUID, event: SIPCallEvent) {
        guard var call = activeCall, call.id == callID else { return }

        switch event {
        case .ended, .remoteEnded:
            finalize(transferred: false)
            return
        case .transferred:
            finalize(transferred: true)
            return
        default:
            break
        }

        switch event {
        case .ringing:
            if call.direction == .outgoing { call.phase = .ringing }
        case .connected:
            call.phase = .active
            call.startedAt = Date()
            startTimer()
        case .held:
            call.phase = .held
        case .resumed:
            call.phase = .active
        case .muted(let m):
            call.isMuted = m
        default:
            break
        }
        activeCall = call
    }

    // MARK: Finalization

    private func finalize(transferred: Bool) {
        guard let call = activeCall else { return }
        stopTimer()
        let answered = transferred || call.phase == .active || call.phase == .held
        let record = CallRecord(
            contactID: call.contact?.id,
            displayName: call.displayName,
            company: call.company,
            number: call.number,
            direction: call.direction,
            date: Date(),
            duration: answered ? elapsed : 0,
            wasAnswered: answered,
            wasTransferred: transferred
        )
        appendRecord(record)
        activeCall = nil
        elapsed = 0
    }

    private func appendRecord(_ record: CallRecord) {
        history.insert(record, at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        persist()
    }

    // MARK: Timer

    private func startTimer() {
        stopTimer()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func tick() {
        guard let call = activeCall, let start = call.startedAt, call.phase == .active || call.phase == .held else { return }
        elapsed = Date().timeIntervalSince(start)
    }

    // MARK: Persistence

    private func persist() {
        store.save(history, to: "history.json")
        store.save(callbackList, to: "callbacks.json")
        store.save(Array(handledMissedIDs), to: "handled.json")
    }
}
