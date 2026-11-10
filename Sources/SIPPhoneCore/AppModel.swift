import Foundation

public extension Notification.Name {
    static let sipSettingsChanged = Notification.Name("sipSettingsChanged")
}

@MainActor
public final class AppModel: ObservableObject {
    public let contacts: ContactStore
    public let devices: DeviceManager
    public let calls: CallManager

    public init() {
        contacts = ContactStore()
        devices = DeviceManager()
        calls = CallManager()
        calls.contactLookup = { [weak contacts] number in
            contacts?.contact(forNumber: number)
        }
        reconnect()

        NotificationCenter.default.addObserver(
            forName: .sipSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconnect() }
        }
    }

    /// (Re)builds the SIP backend from current settings: real client when a server
    /// and username are configured and demo mode is off, simulated client otherwise.
    public func reconnect() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "demoMode": true,
            "sip.port": 5060,
        ])

        let account = SIPAccount(
            server: defaults.string(forKey: "sip.server") ?? "",
            port: defaults.object(forKey: "sip.port") as? Int ?? 5060,
            username: defaults.string(forKey: "sip.username") ?? "",
            password: Keychain.get("sip.password") ?? "",
            displayName: defaults.string(forKey: "sip.displayName") ?? "",
            ownNumber: defaults.string(forKey: "sip.ownNumber") ?? "0221 4710113",
            registrar: defaults.string(forKey: "sip.registrar") ?? ""
        )

        let useDemo = defaults.bool(forKey: "demoMode") || account.server.isEmpty || account.username.isEmpty
        calls.swapClient(
            to: useDemo ? DemoSIPClient() : RealSIPClient(),
            account: account
        )
    }

    public func simulateIncomingCall() {
        guard let contact = contacts.randomContact() else { return }
        calls.requestIncoming(from: contact)
    }
}
