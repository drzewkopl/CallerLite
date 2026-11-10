import SwiftUI

struct AddFavoriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var contacts: ContactStore

    let editing: Contact?

    @State private var firstName: String
    @State private var lastName: String
    @State private var company: String
    @State private var number: String
    @State private var avatar: ContactAvatar?
    @State private var importedImages: Set<String> = []
    @State private var didSave = false

    init(editing: Contact? = nil) {
        self.editing = editing
        _firstName = State(initialValue: editing?.firstName ?? "")
        _lastName = State(initialValue: editing?.lastName ?? "")
        _company = State(initialValue: editing?.company ?? "")
        _number = State(initialValue: editing?.number ?? "")
        _avatar = State(initialValue: editing?.avatar)
    }

    private var canSave: Bool {
        !number.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var previewName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editing == nil ? "Favorit hinzufügen" : "Kontakt bearbeiten")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(.plain)
                Button(editing == nil ? "Hinzufügen" : "Sichern") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)

            Divider()

            Form {
                Section("Kontakt") {
                    TextField("Vorname / Name", text: $firstName)
                    TextField("Nachname (optional)", text: $lastName)
                    TextField("Firma (optional)", text: $company)
                    TextField("Rufnummer", text: $number)
                }

                Section("Symbol") {
                    AvatarPicker(
                        avatar: $avatar,
                        previewName: previewName,
                        colorSeed: editing?.colorSeed ?? 0,
                        onImported: { importedImages.insert($0) }
                    )
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 500)
        .onExitCommand { dismiss() }
        .onDisappear {
            if !didSave {
                discardUnusedImports(keep: nil)
            }
        }
    }

    private func discardUnusedImports(keep: String?) {
        for name in importedImages where name != keep {
            AvatarStorage.delete(named: name)
        }
        importedImages.removeAll()
    }

    private func save() {
        if let editing {
            contacts.update(
                editing,
                firstName: firstName,
                lastName: lastName,
                company: company,
                number: number,
                avatar: avatar
            )
        } else {
            contacts.addFavorite(
                firstName: firstName,
                lastName: lastName,
                company: company,
                number: number,
                avatar: avatar
            )
        }
        didSave = true
        let keptImage = avatar?.kind == .image ? avatar?.value : nil
        discardUnusedImports(keep: keptImage)
        dismiss()
    }
}
