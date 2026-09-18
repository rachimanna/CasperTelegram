import SwiftUI

enum CasperTheme {
    /// Цвета аватаров — как в Telegram, зависят от id чата.
    static let avatarColors: [Color] = [
        Color(red: 0.36, green: 0.62, blue: 0.94),
        Color(red: 0.95, green: 0.45, blue: 0.42),
        Color(red: 0.36, green: 0.78, blue: 0.56),
        Color(red: 0.95, green: 0.71, blue: 0.29),
        Color(red: 0.64, green: 0.51, blue: 0.93),
        Color(red: 0.28, green: 0.76, blue: 0.80),
        Color(red: 0.93, green: 0.50, blue: 0.70)
    ]

    static func avatarColor(for index: Int) -> Color {
        avatarColors[abs(index) % avatarColors.count]
    }

    static let ghostGradient = LinearGradient(
        colors: [Color(red: 0.35, green: 0.45, blue: 0.85), Color(red: 0.52, green: 0.35, blue: 0.80)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Стекло iOS 26 там, где оно есть, и материал — там, где его нет.
/// Проверка через compiler(>=6.2) нужна, чтобы проект собирался и старым Xcode.
struct CasperSurface: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
        #else
        content.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

extension View {
    func casperSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(CasperSurface(cornerRadius: cornerRadius))
    }
}

extension Date {
    /// Время для списка чатов: сегодня — часы, на этой неделе — день недели.
    var chatListStamp: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        if calendar.isDateInToday(self) {
            formatter.dateFormat = "HH:mm"
        } else if let week = calendar.date(byAdding: .day, value: -6, to: Date()), self > week {
            formatter.dateFormat = "EEE"
        } else {
            formatter.dateFormat = "dd.MM.yy"
        }
        return formatter.string(from: self)
    }

    var timeStamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    var fullStamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM, HH:mm"
        return formatter.string(from: self)
    }
}

struct AvatarView: View {
    var initials: String
    var colorIndex: Int
    var size: CGFloat = 52

    var body: some View {
        Circle()
            .fill(CasperTheme.avatarColor(for: colorIndex).gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

struct GhostBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.slash.fill")
            Text("Призрак")
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.indigo.opacity(0.18)))
        .foregroundStyle(Color.indigo)
    }
}
