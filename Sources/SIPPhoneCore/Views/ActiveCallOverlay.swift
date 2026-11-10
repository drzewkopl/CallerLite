import SwiftUI

struct ActiveCallOverlay: View {
    @EnvironmentObject var calls: CallManager

    @State private var showKeypad = false
    @State private var showTransfer = false

    var body: some View {
        if let call = calls.activeCall {
            content(call)
                .transition(.opacity)
        }
    }

    // MARK: Content

    private func content(_ call: CallManager.ActiveCall) -> some View {
        ZStack {
            gradient(call.phase)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 48)

                VStack(spacing: 6) {
                    AvatarView(name: call.displayName, colorSeed: call.contact?.colorSeed ?? 3, avatar: call.contact?.avatar, size: 88)

                    Text(call.displayName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.top, 10)

                    Text(call.company ?? call.number)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)

                    Text(statusText(call))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 4)

                    if call.phase == .active || call.phase == .held {
                        Text(Fmt.elapsed(calls.elapsed))
                            .font(.system(size: 28, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 16)

                if showKeypad && call.phase != .incoming {
                    DTMFPad()
                        .padding(.bottom, 20)
                }

                controls(call)
                    .padding(.bottom, 36)
            }
        }
        .sheet(isPresented: $showTransfer) {
            TransferSheet { target in
                calls.transferCall(to: target)
            }
        }
    }

    // MARK: Gradient

    private func gradient(_ phase: CallManager.ActiveCall.Phase) -> LinearGradient {
        switch phase {
        case .incoming:
            LinearGradient(colors: [Color.violet, Color.callGradientOrange], startPoint: .top, endPoint: .bottom)
        case .dialing, .ringing:
            LinearGradient(colors: [Color(red: 0.28, green: 0.20, blue: 0.55), Color(red: 0.78, green: 0.30, blue: 0.60)],
                           startPoint: .top, endPoint: .bottom)
        case .active:
            LinearGradient(colors: [Color.callGradientRed, Color.callGradientOrange], startPoint: .top, endPoint: .bottom)
        case .held:
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ call: CallManager.ActiveCall) -> some View {
        if call.phase == .incoming {
            VStack(spacing: 8) {
                Text("Eingehender Anruf")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 48) {
                    CircleIconButton(
                        systemName: "phone.down.fill",
                        background: .endCallRed,
                        size: 60,
                        iconSize: 22
                    ) {
                        calls.endActiveCall()
                    }
                    .help("Ablehnen")

                    CircleIconButton(
                        systemName: "phone.fill",
                        background: .acceptGreen,
                        size: 60,
                        iconSize: 22
                    ) {
                        calls.answerIncoming()
                    }
                    .help("Annehmen")
                }
            }
        } else {
            VStack(spacing: 20) {
                HStack(spacing: 26) {
                    CircleIconButton(
                        systemName: call.isMuted ? "mic.slash.fill" : "mic.fill",
                        background: call.isMuted ? .white : .white.opacity(0.18),
                        size: 54,
                        iconSize: 18,
                        iconColor: call.isMuted ? Color.callGradientRed : .white
                    ) {
                        calls.toggleMute()
                    }
                    .help("Stumm schalten")

                    CircleIconButton(
                        systemName: "circle.grid.3x3.fill",
                        background: showKeypad ? .white : .white.opacity(0.18),
                        size: 54,
                        iconSize: 18,
                        iconColor: showKeypad ? Color.violet : .white
                    ) {
                        showKeypad.toggle()
                    }
                    .help("Tastenfeld")

                    CircleIconButton(
                        systemName: "pause.fill",
                        background: call.phase == .held ? .white : .white.opacity(0.18),
                        size: 54,
                        iconSize: 18,
                        iconColor: call.phase == .held ? .black : .white
                    ) {
                        calls.toggleHold()
                    }
                    .help("Halten")
                }

                HStack(spacing: 26) {
                    CircleIconButton(
                        systemName: "phone.arrow.up.right",
                        background: .white.opacity(0.18),
                        size: 54,
                        iconSize: 18
                    ) {
                        showTransfer = true
                    }
                    .help("Übergeben")

                    Color.clear.frame(width: 54, height: 54)

                    CircleIconButton(
                        systemName: "phone.down.fill",
                        background: .endCallRed,
                        size: 56,
                        iconSize: 20
                    ) {
                        calls.endActiveCall()
                    }
                    .help("Auflegen")
                }
            }
        }
    }

    private func statusText(_ call: CallManager.ActiveCall) -> String {
        switch call.phase {
        case .dialing: return "Verbindung wird aufgebaut…"
        case .ringing: return "Es klingelt…"
        case .incoming: return ""
        case .active: return "Verbunden"
        case .held: return "Gehalten"
        }
    }
}

// MARK: - DTMF pad (in-call)

struct DTMFPad: View {
    @EnvironmentObject var calls: CallManager
    @State private var entered = ""

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"],
    ]
    private let letters = ["2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL",
                           "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ", "0": "+"]

    var body: some View {
        VStack(spacing: 10) {
            Text(entered.isEmpty ? " " : entered)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(height: 24)

            VStack(spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                entered += key
                                calls.sendDTMF(key)
                            } label: {
                                VStack(spacing: 1) {
                                    Text(key)
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(letters[key] ?? "")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 42)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.15))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Transfer sheet

struct TransferSheet: View {
    @EnvironmentObject var contacts: ContactStore
    @Environment(\.dismiss) private var dismiss

    let onPick: (Contact) -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Übergeben an")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            TextField("Name oder Nummer suchen", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 2) {
                    let found = query.isEmpty ? contacts.contacts : contacts.filtered(by: query)
                    ForEach(found) { contact in
                        Button {
                            onPick(contact)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                AvatarView(name: contact.displayName, colorSeed: contact.colorSeed, avatar: contact.avatar, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(contact.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(contact.number)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "phone.arrow.up.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if found.isEmpty {
                        EmptyRow(text: "Keine Kontakte gefunden")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 320, height: 420)
    }
}
