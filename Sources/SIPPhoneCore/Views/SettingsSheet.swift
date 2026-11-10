import SwiftUI

struct SettingsSheet: View {
    let size: CGSize
    @Environment(\.dismiss) private var dismiss

    @AppStorage("sip.server") private var server = ""
    @AppStorage("sip.port") private var port: Int = 5060
    @AppStorage("sip.registrar") private var registrar = ""
    @AppStorage("sip.username") private var username = ""
    @AppStorage("sip.displayName") private var displayName = ""
    @AppStorage("sip.ownNumber") private var ownNumber = "0221 4710113"
    @AppStorage("demoMode") private var demoMode = true

    @State private var password = Keychain.get("sip.password") ?? ""
    @State private var serverMissing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Einstellungen")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Fertig") { dismiss() }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)

            Divider()

            Form {
                Section("SIP-Konto") {
                    TextField("Server (z. B. sip.example.com)", text: $server)
                    TextField("Port (UDP)", value: $port, format: .number)
                    TextField("Registrar (optional, Host[:Port])", text: $registrar)
                    TextField("Benutzer", text: $username)
                    SecureField("Passwort", text: $password)
                    TextField("Anzeigename", text: $displayName)
                    TextField("Eigene Rufnummer", text: $ownNumber)
                }

                Section {
                    Toggle("Demo-Modus (simulierte Anrufe)", isOn: $demoMode)
                    if !demoMode && server.isEmpty {
                        Label("Server-Adresse erforderlich, sonst bleibt der Demo-Modus aktiv.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Text("Mit den Zugangsdaten registriert sich die App per SIP über UDP beim Server. Ist ein Registrar angegeben, laufen Registrierung und Anrufe über ihn (Host:Port, Standardport = SIP-Port). Unterstützt: G.711 (PCMU/PCMA), Halten, Übergeben, DTMF. Das Passwort wird im Schlüsselbund gespeichert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: size.width, height: size.height)
        .onExitCommand { dismiss() }
        .onDisappear {
            Keychain.set(password, account: "sip.password")
            NotificationCenter.default.post(name: .sipSettingsChanged, object: nil)
        }
    }
}
