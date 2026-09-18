import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CasperHomeView()
                    } label: {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(CasperTheme.ghostGradient)
                                .frame(width: 40, height: 40)
                                .overlay(Image(systemName: "moon.stars.fill").foregroundStyle(.white))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Casper").font(.body.weight(.semibold))
                                Text("Your Telegram. Your rules.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if environment.isGhostActive { GhostBadge() }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Оформление") {
                    NavigationLink { AppearanceView() } label: {
                        Label("Внешний вид", systemImage: "paintpalette")
                    }
                }

                Section("Состояние") {
                    LabeledContent("Соединение", value: environment.connection.title)
                    LabeledContent("Режим", value: environment.telegram.isDemo ? "Демо (без TDLib)" : "Telegram")
                    LabeledContent("Версия", value: AppInfo.version)
                }

                Section {
                    Button(role: .destructive) {
                        Task { await environment.logOut() }
                    } label: {
                        Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
