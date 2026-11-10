import Foundation

// MARK: - Contact

public struct ContactAvatar: Codable, Hashable {
    public enum Kind: String, Codable {
        case emoji
        case image
    }

    public var kind: Kind
    public var value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }
}

public struct Contact: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var firstName: String
    public var lastName: String
    public var company: String?
    public var number: String
    public var isFavorite: Bool = false
    public var colorSeed: Int = Int.random(in: 0...5)
    public var avatar: ContactAvatar?

    public var displayName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Availability (Telefonstatus)

public enum Availability: String, CaseIterable, Codable {
    case available
    case away
    case busy
    case doNotDisturb

    public var title: String {
        switch self {
        case .available: return "Erreichbar"
        case .away: return "Abwesend"
        case .busy: return "Beschäftigt"
        case .doNotDisturb: return "Nicht stören"
        }
    }

    public var symbol: String {
        switch self {
        case .available: return "checkmark.circle"
        case .away: return "clock"
        case .busy: return "minus.circle"
        case .doNotDisturb: return "bell.slash.fill"
        }
    }

    /// Only these statuses let incoming calls ring through.
    public var acceptsCalls: Bool {
        self == .available || self == .away
    }
}

// MARK: - Call records

public enum CallDirection: String, Codable {
    case incoming
    case outgoing
}

public struct CallRecord: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var contactID: UUID?
    public var displayName: String
    public var company: String?
    public var number: String
    public var direction: CallDirection
    public var date: Date
    public var duration: TimeInterval
    public var wasAnswered: Bool
    public var wasTransferred: Bool = false

    var wasMissed: Bool { !wasAnswered && direction == .incoming }
    public var subtitle: String {
        [company, number].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct CallbackEntry: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var contactID: UUID?
    public var displayName: String
    public var company: String?
    public var number: String
    public var addedAt: Date = Date()
}

// MARK: - Helpers

func normalizedNumber(_ s: String) -> String {
    String(s.filter { "+0123456789".contains($0) })
}

enum Fmt {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeStyle = .short
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM."
        return f
    }()

    static func callTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute " + time.string(from: date) }
        if cal.isDateInYesterday(date) { return "Gestern " + time.string(from: date) }
        return day.string(from: date) + " " + time.string(from: date)
    }

    static func duration(_ t: TimeInterval) -> String {
        guard t > 0 else { return "" }
        let s = Int(t)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func elapsed(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }

    /// A clock time on a recent day; if `hour:minute` today lies in the
    /// future, the date is shifted into the past so seeds always look plausible.
    static func recentDate(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        guard var d = Calendar.current.date(from: comps) else { return Date() }
        if d > Date() {
            d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return d
    }
}

// MARK: - Seed data

extension Contact {
    static let seed: [Contact] = {
        func c(_ first: String, _ last: String, _ company: String?, _ number: String, fav: Bool = false, seed: Int) -> Contact {
            Contact(firstName: first, lastName: last, company: company, number: number, isFavorite: fav, colorSeed: seed)
        }
        return [
            c("Felix", "Möller", "Möller Media", "+49 221 5550111", fav: true, seed: 0),
            c("Carrie", "Novak", "Circles GmbH", "+49 221 5550142", fav: true, seed: 1),
            c("Henry", "Weber", "Weber & Söhne", "+49 221 5550177", fav: true, seed: 2),
            c("Marie", "Schmitz", "Studio Nord", "+49 221 5550104", fav: true, seed: 3),
            c("Katharina", "Braun", "Hafen Logistik", "+49 221 5550198", fav: true, seed: 4),
            c("Torsten", "Schroers", "ACME Inc.", "+49 221 4708200", seed: 5),
            c("Leona", "Krause", "Hafenquelle UG", "+49 221 9550402", seed: 0),
            c("Alfredo", "Martines", "Next Flowers Ltd.", "+49 89 32040117", seed: 1),
            c("Ingredia", "Nutrisha", "Ingredia GmbH", "+49 30 55578900", seed: 2),
            c("Miles", "Tone", "Tone Records", "+49 30 55578142", seed: 3),
            c("Anna", "Strudelsen", "Strudelsen Bäckerei", "+49 221 6600981", seed: 4),
            c("Bernd", "Petersen", "Nordwind AG", "+49 431 887766", seed: 5),
            c("Sabine", "Albers", "Albers & Partner", "+49 221 334455", seed: 0),
            c("Yusuf", "Demir", "Demir Immobilien", "+49 221 9981123", seed: 1),
        ]
    }()
}

extension CallRecord {
    static let seed: [CallRecord] = {
        let torsten = Contact.seed.first { $0.lastName == "Schroers" }!
        let marie = Contact.seed.first { $0.lastName == "Schmitz" }!
        let alfredo = Contact.seed.first { $0.lastName == "Martines" }!
        let katharina = Contact.seed.first { $0.lastName == "Braun" }!

        return [
            CallRecord(
                contactID: torsten.id,
                displayName: torsten.displayName,
                company: torsten.company,
                number: torsten.number,
                direction: .incoming,
                date: Fmt.recentDate(hour: 10, minute: 37),
                duration: 0,
                wasAnswered: false
            ),
            CallRecord(
                contactID: katharina.id,
                displayName: katharina.displayName,
                company: katharina.company,
                number: katharina.number,
                direction: .outgoing,
                date: Fmt.recentDate(hour: 8, minute: 15),
                duration: 312,
                wasAnswered: true
            ),
            CallRecord(
                contactID: marie.id,
                displayName: marie.displayName,
                company: marie.company,
                number: marie.number,
                direction: .outgoing,
                date: Calendar.current.date(byAdding: .day, value: -1, to: Fmt.recentDate(hour: 18, minute: 2)) ?? Date(),
                duration: 134,
                wasAnswered: true
            ),
            CallRecord(
                contactID: alfredo.id,
                displayName: alfredo.displayName,
                company: alfredo.company,
                number: alfredo.number,
                direction: .incoming,
                date: Calendar.current.date(byAdding: .day, value: -1, to: Fmt.recentDate(hour: 9, minute: 21)) ?? Date(),
                duration: 27,
                wasAnswered: true
            ),
            CallRecord(
                contactID: nil,
                displayName: "Unbekannter Anrufer",
                company: nil,
                number: "+49 221 9980010",
                direction: .incoming,
                date: Calendar.current.date(byAdding: .day, value: -2, to: Fmt.recentDate(hour: 16, minute: 45)) ?? Date(),
                duration: 0,
                wasAnswered: false
            ),
        ]
    }()
}

extension CallbackEntry {
    static let seed: [CallbackEntry] = {
        let torsten = Contact.seed.first { $0.lastName == "Schroers" }!
        let leona = Contact.seed.first { $0.lastName == "Krause" }!
        return [
            CallbackEntry(contactID: torsten.id, displayName: torsten.displayName, company: torsten.company, number: torsten.number),
            CallbackEntry(contactID: leona.id, displayName: leona.displayName, company: leona.company, number: leona.number),
        ]
    }()
}
