import SwiftUI

struct BottomBar: View {
    @EnvironmentObject var devices: DeviceManager
    @EnvironmentObject var calls: CallManager
    @AppStorage("sip.ownNumber") private var ownNumber = "0221 4710113"

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)

            HStack(spacing: 8) {
                deviceMenu(icon: "mic.fill", kind: .input)
                deviceMenu(icon: "headphones", kind: .output)
                ownNumberBox
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private enum DeviceKind { case input, output }

    private func deviceMenu(icon: String, kind: DeviceKind) -> some View {
        let list = kind == .input ? devices.inputDevices : devices.outputDevices
        let selected = kind == .input ? devices.selectedInput : devices.selectedOutput
        let fallback = kind == .input ? "Kein Mikrofon" : "Systemstandard"

        return Menu {
            if list.isEmpty {
                Text("Keine Geräte gefunden")
            } else {
                ForEach(list) { device in
                    Button {
                        if kind == .input {
                            devices.selectInput(device)
                        } else {
                            devices.selectOutput(device)
                        }
                    } label: {
                        if (kind == .input && device.isDefaultInput)
                            || (kind == .output && device.isDefaultOutput) {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            }
        } label: {
            DeviceBoxLabel(icon: icon, title: selected?.name ?? fallback)
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.borderlessButton)
        .help(kind == .input ? "Mikrofon wählen" : "Lautsprecher/Kopfhörer wählen")
    }

    private var ownNumberBox: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .help(statusText)
            VStack(alignment: .leading, spacing: 0) {
                Text("Eigene Rufnummer")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                Text(ownNumber.isEmpty ? "–" : ownNumber)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var statusColor: Color {
        switch calls.registration {
        case .demo: return .gray
        case .connecting: return .orange
        case .registered: return .acceptGreen
        case .failed: return .endCallRed
        }
    }

    private var statusText: String {
        switch calls.registration {
        case .demo: return "Demo-Modus (kein SIP-Server verbunden)"
        case .connecting: return "Verbinde mit SIP-Server…"
        case .registered: return "Registriert"
        case .failed(let reason): return "Nicht registriert: \(reason)"
        }
    }
}

struct DeviceBoxLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .contentShape(Rectangle())
    }
}
