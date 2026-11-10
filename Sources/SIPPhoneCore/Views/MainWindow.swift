import SwiftUI

public struct MainWindow: View {
    @EnvironmentObject var calls: CallManager
    @EnvironmentObject var contacts: ContactStore

    @State private var query = ""
    @State private var showKeypad = false
    @State private var showSettings = false
    @State private var showAddFavorite = false
    @State private var editingContact: Contact?
    @State private var showStatusMenu = false
    @State private var windowSize = CGSize(width: 400, height: 700)

    public init() {}

    private var isDialableQuery: Bool {
        let t = query.filter { !$0.isWhitespace }
        guard !t.isEmpty else { return false }
        let digits = t.filter(\.isNumber)
        return digits.count >= 3 && t.allSatisfy { "0123456789+-()".contains($0) }
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)

                if query.isEmpty {
                    favoritesBar
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                }

                if query.isEmpty {
                    sections
                } else {
                    results
                }

                BottomBar()
            }

            if calls.activeCall != nil {
                ActiveCallOverlay()
            }
        }
        .frame(minWidth: 360, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowSizeNormalizer { windowSize = $0 })
        .overlay(alignment: .top) {
            Text("CallerLite")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, -22)
                .allowsHitTesting(false)
        }
        .popover(isPresented: $showKeypad, arrowEdge: .bottom) {
            KeypadView()
                .padding(16)
                .frame(width: 236, height: 364)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(size: windowSize)
        }
        .sheet(isPresented: $showAddFavorite) {
            AddFavoriteSheet()
                .environmentObject(contacts)
        }
        .sheet(item: $editingContact) { contact in
            AddFavoriteSheet(editing: contact)
                .environmentObject(contacts)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            statusMenu

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                TextField("Nummer oder Name eingeben", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { dialPrimaryResult() }
                if !query.isEmpty {
                    if isDialableQuery {
                        CircleIconButton(
                            systemName: "phone.fill",
                            background: .acceptGreen,
                            size: 24,
                            iconSize: 11
                        ) {
                            dialRawNumber(query)
                        }
                        .help("Nummer anrufen")
                    }
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Suche löschen")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08))
            )

            ToolBarButton(systemName: "circle.grid.3x3.fill", helpText: "Tastenfeld") {
                showKeypad = true
            }
            ToolBarButton(systemName: "gearshape.fill", helpText: "Einstellungen") {
                showSettings = true
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: Availability

    private var statusMenu: some View {
        Button {
            showStatusMenu.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor(calls.availability))
                    .frame(width: 8, height: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Telefonstatus: \(calls.availability.title) – „Nicht stören“ lehnt eingehende Anrufe stumm ab")
        .popover(isPresented: $showStatusMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Telefonstatus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 3)

                ForEach(Availability.allCases, id: \.self) { status in
                    Button {
                        calls.setAvailability(status)
                        showStatusMenu = false
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor(status))
                                .frame(width: 8, height: 8)
                            Text(status.title)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 12)
                            if status == calls.availability {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 180)
        }
    }

    private func statusColor(_ status: Availability) -> Color {
        switch status {
        case .available: return .acceptGreen
        case .away: return .orange
        case .busy, .doNotDisturb: return .endCallRed
        }
    }

    // MARK: Favorites

    private var favoritesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(contacts.favorites) { contact in
                    Button {
                        calls.placeCall(contact)
                    } label: {
                        VStack(spacing: 5) {
                            AvatarView(name: contact.displayName, colorSeed: contact.colorSeed, avatar: contact.avatar, size: 44)
                            Text(contact.firstName)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("\(contact.displayName) anrufen")
                    .contextMenu {
                        Button("Bearbeiten…") {
                            editingContact = contact
                        }
                        Button("Aus Favoriten entfernen") {
                            contacts.toggleFavorite(contact)
                        }
                    }
                }

                Button {
                    showAddFavorite = true
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle().fill(Color.primary.opacity(0.08))
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 44, height: 44)
                        Text("Hinzufügen")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Favorit hinzufügen")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: Sections

    private var sections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                missedSection
                callbackSection
                historySection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var missedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Verpasste Anrufe", count: calls.missedTodayCount, color: .red)
            if calls.missedRecords.isEmpty {
                EmptyRow(text: "Keine verpassten Anrufe")
            } else {
                ForEach(Array(calls.missedRecords.prefix(6))) { record in
                    MissedRow(record: record)
                }
            }
        }
    }

    private var callbackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Rückrufliste", count: calls.callbackList.count, color: .orange)
            if calls.callbackList.isEmpty {
                EmptyRow(text: "Keine offenen Rückrufe")
            } else {
                ForEach(calls.callbackList) { entry in
                    CallbackRow(entry: entry)
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Anrufverlauf", color: .accentColor)
            if calls.history.isEmpty {
                EmptyRow(text: "Noch keine Anrufe")
            } else {
                ForEach(calls.history) { record in
                    HistoryRow(record: record)
                }
            }
        }
    }

    // MARK: Search results

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Suchergebnisse", color: .accentColor)

                if isDialableQuery {
                    dialRow
                }

                let found = contacts.filtered(by: query)
                ForEach(found) { contact in
                    ContactRow(contact: contact)
                }
                if found.isEmpty && !isDialableQuery {
                    EmptyRow(text: "Keine Kontakte gefunden")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var dialRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "phone.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.acceptGreen)
            VStack(alignment: .leading, spacing: 1) {
                Text("„\(query)“ anrufen")
                    .font(.system(size: 13, weight: .semibold))
                Text("Nummer direkt wählen")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CircleIconButton(systemName: "phone.fill", background: .acceptGreen, size: 28) {
                dialRawNumber(query)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { dialRawNumber(query) }
    }

    // MARK: Actions

    private func dialPrimaryResult() {
        let found = contacts.filtered(by: query)
        if let first = found.first {
            calls.placeCall(first)
            query = ""
        } else if isDialableQuery {
            dialRawNumber(query)
        }
    }

    private func dialRawNumber(_ number: String) {
        guard let contact = contacts.contact(forNumber: number) else {
            calls.placeCall(number: number)
            query = ""
            return
        }
        calls.placeCall(contact)
        query = ""
    }
}

private struct WindowSizeNormalizer: NSViewRepresentable {
    let onSizeChange: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSizeChange: onSizeChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let window = view.window else { return }
            let key = "sip.windowNormalized400"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                var frame = window.frame
                if abs(frame.width - 400) > 0.5 {
                    frame.size.width = 400
                    frame.size.height = 700
                    window.setFrame(frame, display: true, animate: false)
                }
            }
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private let onSizeChange: (CGSize) -> Void
        private weak var window: NSWindow?

        init(onSizeChange: @escaping (CGSize) -> Void) {
            self.onSizeChange = onSizeChange
        }

        func attach(to window: NSWindow) {
            self.window = window
            onSizeChange(window.frame.size)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResize(_:)),
                name: NSWindow.didResizeNotification,
                object: window
            )
        }

        @objc private func windowDidResize(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            onSizeChange(window.frame.size)
        }
    }
}
