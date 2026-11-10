import Foundation

@MainActor
public final class ContactStore: ObservableObject {
    @Published private(set) var contacts: [Contact] = []

    private let store = JSONStore(name: "SIPPhone")

    public init() {
        if let saved = store.load([Contact].self, from: "contacts.json") {
            contacts = saved
        } else {
            contacts = Contact.seed
            save()
        }
    }

    var favorites: [Contact] { contacts.filter(\.isFavorite) }

    func filtered(by query: String) -> [Contact] {
        guard !query.isEmpty else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let nq = normalizedNumber(q)
        return contacts.filter { c in
            c.displayName.lowercased().contains(q)
                || (c.company?.lowercased().contains(q) ?? false)
                || (nq.count > 2 && normalizedNumber(c.number).contains(nq))
        }
    }

    func contact(forNumber number: String) -> Contact? {
        let n = normalizedNumber(number)
        return contacts.first { normalizedNumber($0.number) == n }
    }

    func randomContact() -> Contact? { contacts.randomElement() }

    func toggleFavorite(_ contact: Contact) {
        guard let idx = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[idx].isFavorite.toggle()
        save()
    }

    /// Adds a new favorite (or promotes an existing contact with the same number).
    func addFavorite(
        firstName: String,
        lastName: String = "",
        company: String? = nil,
        number: String,
        avatar: ContactAvatar? = nil
    ) {
        let trimmedNumber = number.trimmingCharacters(in: .whitespaces)
        guard !trimmedNumber.isEmpty else { return }
        let n = normalizedNumber(trimmedNumber)

        if let idx = contacts.firstIndex(where: { normalizedNumber($0.number) == n }) {
            contacts[idx].isFavorite = true
            if let avatar {
                applyAvatar(avatar, at: idx)
            }
            save()
            return
        }

        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        let comp = company?.trimmingCharacters(in: .whitespaces) ?? ""
        contacts.append(Contact(
            firstName: first.isEmpty ? trimmedNumber : first,
            lastName: last,
            company: comp.isEmpty ? nil : comp,
            number: trimmedNumber,
            isFavorite: true,
            avatar: avatar
        ))
        save()
    }

    /// Updates the editable fields of an existing contact.
    func update(
        _ contact: Contact,
        firstName: String,
        lastName: String,
        company: String?,
        number: String,
        avatar: ContactAvatar?
    ) {
        guard let idx = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedNumber = number.trimmingCharacters(in: .whitespaces)
        let comp = company?.trimmingCharacters(in: .whitespaces) ?? ""

        contacts[idx].firstName = first.isEmpty ? trimmedNumber : first
        contacts[idx].lastName = lastName.trimmingCharacters(in: .whitespaces)
        contacts[idx].company = comp.isEmpty ? nil : comp
        contacts[idx].number = trimmedNumber
        applyAvatar(avatar, at: idx)
        save()
    }

    private func applyAvatar(_ avatar: ContactAvatar?, at idx: Int) {
        let old = contacts[idx].avatar
        contacts[idx].avatar = avatar
        if let old, old != avatar, old.kind == .image {
            AvatarStorage.delete(named: old.value)
        }
    }

    func isFavorite(number: String) -> Bool {
        let n = normalizedNumber(number)
        return contacts.first { normalizedNumber($0.number) == n }?.isFavorite ?? false
    }

    private func save() {
        store.save(contacts, to: "contacts.json")
    }
}
