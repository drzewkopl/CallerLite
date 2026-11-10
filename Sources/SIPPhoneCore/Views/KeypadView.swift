import SwiftUI

struct KeypadView: View {
    @EnvironmentObject var calls: CallManager
    @Environment(\.dismiss) private var dismiss

    @State private var digits = ""

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"],
    ]
    private let letters = ["2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL",
                           "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ", "0": "+"]

    var body: some View {
        VStack(spacing: 12) {
            Text(digits.isEmpty ? " " : digits)
                .font(.system(size: 24, weight: .semibold))
                .monospacedDigit()
                .frame(height: 36)

            VStack(spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                digits += key
                            } label: {
                                VStack(spacing: 1) {
                                    Text(key)
                                        .font(.system(size: 19, weight: .semibold))
                                    Text(letters[key] ?? "")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 58, height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color.primary.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                Color.clear.frame(width: 44, height: 44)

                Button {
                    if !digits.isEmpty { digits.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(digits.isEmpty)

                Spacer()

                CircleIconButton(
                    systemName: "phone.fill",
                    background: .acceptGreen,
                    size: 48,
                    iconSize: 18
                ) {
                    guard !digits.isEmpty else { return }
                    calls.placeCall(number: digits)
                    dismiss()
                }
                .disabled(digits.isEmpty)
                .opacity(digits.isEmpty ? 0.4 : 1)
                .help("Anrufen")
            }
            .padding(.top, 2)
        }
    }
}
