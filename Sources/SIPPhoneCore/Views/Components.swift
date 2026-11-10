import SwiftUI

extension Color {
    static let avatarPalette: [Color] = [
        Color(red: 0.45, green: 0.35, blue: 0.95),
        Color(red: 0.95, green: 0.45, blue: 0.25),
        Color(red: 0.20, green: 0.65, blue: 0.85),
        Color(red: 0.85, green: 0.35, blue: 0.55),
        Color(red: 0.25, green: 0.70, blue: 0.55),
        Color(red: 0.90, green: 0.65, blue: 0.20),
    ]

    static let callGradientRed = Color(red: 0.93, green: 0.22, blue: 0.15)
    static let callGradientOrange = Color(red: 1.00, green: 0.45, blue: 0.10)
    static let endCallRed = Color(red: 0.85, green: 0.16, blue: 0.16)
    static let acceptGreen = Color(red: 0.18, green: 0.68, blue: 0.36)
    static let violet = Color(red: 0.42, green: 0.30, blue: 0.90)
}

struct AvatarView: View {
    let name: String
    let colorSeed: Int
    var avatar: ContactAvatar? = nil
    var size: CGFloat = 44

    var body: some View {
        avatarContent
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let avatar {
            if avatar.kind == .emoji {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.08))
                    Text(avatar.value)
                        .font(.system(size: size * 0.56))
                }
            } else if let image = AvatarStorage.image(named: avatar.value) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                initialsView
            }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
        return ZStack {
            Circle().fill(Color.avatarPalette[colorSeed % Color.avatarPalette.count].gradient)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct CircleIconButton: View {
    let systemName: String
    var background: Color = .accentColor
    var size: CGFloat = 28
    var iconSize: CGFloat = 12
    var iconColor: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
        }
        .buttonStyle(.plain)
    }
}

struct ToolBarButton: View {
    let systemName: String
    var helpText: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var color: Color = .red

    init(_ title: String, count: Int? = nil, color: Color = .red) {
        self.title = title
        self.count = count
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let c = count, c > 0 {
                Text("\(c)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(color))
            }
            Spacer()
        }
    }
}

struct EmptyRow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .italic()
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}
