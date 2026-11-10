import SwiftUI

// MARK: - Missed call row

struct MissedRow: View {
    @EnvironmentObject var calls: CallManager
    @EnvironmentObject var contacts: ContactStore

    let record: CallRecord
    @State private var hover = false
    @State private var editingContact: Contact?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "phone.arrow.down.left.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.red)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(record.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(Fmt.callTime(record.date))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button {
                calls.addToCallbacks(record)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Zur Rückrufliste hinzufügen")

            CircleIconButton(systemName: "phone.fill", background: .acceptGreen, size: 26, iconSize: 11) {
                dial(record)
            }
            .help("Rückruf")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hover ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { dial(record) }
        .onHover { hover = $0 }
        .contextMenu {
            Button("Rückruf") { dial(record) }
            Button("Zur Rückrufliste hinzufügen") { calls.addToCallbacks(record) }
            if let contact = contacts.contact(forNumber: record.number) {
                Button("Bearbeiten…") { editingContact = contact }
                Button(contact.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                    contacts.toggleFavorite(contact)
                }
            } else {
                Button("Zu Favoriten hinzufügen") {
                    contacts.addFavorite(firstName: record.displayName, number: record.number)
                }
            }
        }
        .sheet(item: $editingContact) { contact in
            AddFavoriteSheet(editing: contact)
                .environmentObject(contacts)
        }
    }

    private func dial(_ record: CallRecord) {
        let contact = contacts.contact(forNumber: record.number)
        calls.placeCall(
            number: record.number,
            displayName: contact?.displayName ?? record.displayName,
            company: contact?.company ?? record.company,
            contact: contact
        )
        calls.markHandled(record.id)
    }
}

// MARK: - Callback row

struct CallbackRow: View {
    @EnvironmentObject var calls: CallManager
    @EnvironmentObject var contacts: ContactStore

    let entry: CallbackEntry
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "phone.arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text([entry.company, entry.number].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                calls.removeFromCallbacks(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Aus Rückrufliste entfernen")

            CircleIconButton(systemName: "phone.fill", background: .acceptGreen, size: 26, iconSize: 11) {
                dial()
            }
            .help("Jetzt zurückrufen")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hover ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { dial() }
        .onHover { hover = $0 }
    }

    private func dial() {
        let contact = contacts.contact(forNumber: entry.number)
        calls.placeCall(
            number: entry.number,
            displayName: contact?.displayName ?? entry.displayName,
            company: contact?.company ?? entry.company,
            contact: contact
        )
        calls.removeFromCallbacks(entry)
    }
}

// MARK: - History row

struct HistoryRow: View {
    @EnvironmentObject var calls: CallManager
    @EnvironmentObject var contacts: ContactStore

    let record: CallRecord
    @State private var hover = false
    @State private var editingContact: Contact?

    private var icon: String {
        if record.wasTransferred { return "phone.arrow.up.right.fill" }
        switch (record.direction, record.wasAnswered) {
        case (.incoming, false): return "phone.arrow.down.left.fill"
        case (.incoming, true): return "phone.arrow.down.left"
        case (.outgoing, _): return "phone.arrow.up.right"
        }
    }

    private var iconColor: Color {
        if record.wasTransferred { return .orange }
        switch (record.direction, record.wasAnswered) {
        case (.incoming, false): return .red
        case (.incoming, true): return .secondary
        case (.outgoing, _): return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.displayName)
                    .font(.system(size: 13, weight: record.wasMissed ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(record.wasMissed ? Color.primary : Color.primary.opacity(0.85))
                Text(record.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.callTime(record.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if record.wasTransferred {
                    Text("Übergeben")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                } else if record.wasAnswered {
                    Text(Fmt.duration(record.duration))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hover ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { dial() }
        .onHover { hover = $0 }
        .contextMenu {
            Button("Rückruf") { dial() }
            Button("Zur Rückrufliste hinzufügen") {
                calls.addToCallbacks(record)
            }
            if let contact = contacts.contact(forNumber: record.number) {
                Button("Bearbeiten…") { editingContact = contact }
                Button(contact.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                    contacts.toggleFavorite(contact)
                }
            } else {
                Button("Zu Favoriten hinzufügen") {
                    contacts.addFavorite(firstName: record.displayName, number: record.number)
                }
            }
            Divider()
            Button("Aus Verlauf entfernen", role: .destructive) {
                calls.deleteRecord(record.id)
            }
        }
        .sheet(item: $editingContact) { contact in
            AddFavoriteSheet(editing: contact)
                .environmentObject(contacts)
        }
    }

    private func dial() {
        let contact = contacts.contact(forNumber: record.number)
        calls.placeCall(
            number: record.number,
            displayName: contact?.displayName ?? record.displayName,
            company: contact?.company ?? record.company,
            contact: contact
        )
    }
}

// MARK: - Contact row (search results)

struct ContactRow: View {
    @EnvironmentObject var calls: CallManager
    @EnvironmentObject var contacts: ContactStore

    let contact: Contact
    @State private var hover = false
    @State private var editingContact: Contact?

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(name: contact.displayName, colorSeed: contact.colorSeed, avatar: contact.avatar, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text([contact.company, contact.number].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            CircleIconButton(systemName: "phone.fill", background: .acceptGreen, size: 26, iconSize: 11) {
                calls.placeCall(contact)
            }
            .help("Anrufen")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hover ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { calls.placeCall(contact) }
        .onHover { hover = $0 }
        .contextMenu {
            Button("Anrufen") { calls.placeCall(contact) }
            Button("Bearbeiten…") { editingContact = contact }
            Button(contact.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                contacts.toggleFavorite(contact)
            }
        }
        .sheet(item: $editingContact) { contact in
            AddFavoriteSheet(editing: contact)
                .environmentObject(contacts)
        }
    }
}
