import SwiftUI
import UniformTypeIdentifiers

struct AvatarPicker: View {
    @Binding var avatar: ContactAvatar?
    let previewName: String
    let colorSeed: Int
    var onImported: (String) -> Void = { _ in }

    @State private var showImporter = false
    @State private var showError = false

    static let standardEmojis: [String] = [
        "🧑", "👩", "👨", "🧔", "👱‍♀️", "👱‍♂️", "👩‍🦰",
        "👨‍🦰", "👩‍🦱", "👨‍🦱", "👩‍🦳", "👨‍🦳", "👩‍💼",
        "👨‍💼", "👩‍💻", "👨‍💻", "👩‍🎨", "👨‍🎨", "👩‍🔬",
        "👨‍🔬", "🧑‍🚀", "🧑‍🍳", "👩‍🏫", "👨‍🏫", "👮‍♀️",
        "👮‍♂️", "🕵️‍♀️", "🕵️‍♂️",
    ]

    private var selectedEmoji: String? {
        guard let avatar, avatar.kind == .emoji else { return nil }
        return avatar.value
    }

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(name: previewName, colorSeed: colorSeed, avatar: avatar, size: 64)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Standard-Symbole")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Self.standardEmojis, id: \.self) { emoji in
                            Button {
                                avatar = ContactAvatar(kind: .emoji, value: emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 19))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        Circle().fill(
                                            selectedEmoji == emoji
                                                ? Color.accentColor.opacity(0.30)
                                                : Color.primary.opacity(0.06)
                                        )
                                    )
                                    .overlay(
                                        Circle().strokeBorder(
                                            selectedEmoji == emoji ? Color.accentColor : .clear,
                                            lineWidth: 1.5
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Als Symbol verwenden")
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Bild wählen…") { showImporter = true }
                if avatar != nil {
                    Button("Symbol entfernen") { avatar = nil }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                if let filename = AvatarStorage.importImage(from: url) {
                    onImported(filename)
                    avatar = ContactAvatar(kind: .image, value: filename)
                } else {
                    showError = true
                }
            case .failure:
                showError = true
            }
        }
        .alert("Bild konnte nicht geladen werden", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
    }
}
