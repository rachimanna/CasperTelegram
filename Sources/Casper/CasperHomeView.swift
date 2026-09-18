import SwiftUI

struct CasperHomeView: View {
    @EnvironmentObject private var environment: AppEnvironment

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero

                LazyVGrid(columns: columns, spacing: 14) {
                    NavigationLink { GhostView() } label: {
                        FeatureCard(emoji: "👻",
                                    title: "Призрак",
                                    subtitle: "Контролируйте отображение своего присутствия.",
                                    isOn: environment.isGhostActive)
                    }
                    NavigationLink { DeletedMessagesView() } label: {
                        FeatureCard(emoji: "🗑",
                                    title: "Удалённые сообщения",
                                    subtitle: "Локальные копии сообщений, которые Casper уже получил.",
                                    isOn: environment.settings.archive.isEnabled)
                    }
                    NavigationLink { OfflineModeView() } label: {
                        FeatureCard(emoji: "📴",
                                    title: "Офлайн",
                                    subtitle: "Кто видит ваш статус «был(а) в сети».",
                                    isOn: environment.settings.privacy.showStatus.visibility != .everybody)
                    }
                    NavigationLink { VoiceChangerView(targetChat: nil) } label: {
                        FeatureCard(emoji: "🎙",
                                    title: "Voice Changer",
                                    subtitle: "Меняйте голос перед отправкой. Локально, без сервисов.",
                                    isOn: false)
                    }
                    NavigationLink { IntegrationsView() } label: {
                        FeatureCard(emoji: "🔑",
                                    title: "Интеграции",
                                    subtitle: "Свой ключ AI-сервиса для расшифровки голосовых.",
                                    isOn: environment.settings.integration.isEnabled)
                    }
                    NavigationLink { AppearanceView() } label: {
                        FeatureCard(emoji: "🎨",
                                    title: "Внешний вид",
                                    subtitle: "Тема, акцент, плотность списка чатов.",
                                    isOn: false)
                    }
                }

                NavigationLink { AboutCasperView() } label: {
                    HStack {
                        Label("О Casper", systemImage: "info.circle")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .casperSurface(cornerRadius: 18)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .navigationTitle("Casper")
        .background(Color(.systemGroupedBackground))
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Text("CASPER")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .tracking(6)
                .foregroundStyle(CasperTheme.ghostGradient)
            Text("Your Telegram. Your rules.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .casperSurface(cornerRadius: 24)
    }
}

struct FeatureCard: View {
    var emoji: String
    var title: String
    var subtitle: String
    var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(emoji).font(.system(size: 26))
                Spacer()
                if isOn {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                }
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(height: 150, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .casperSurface(cornerRadius: 20)
    }
}
