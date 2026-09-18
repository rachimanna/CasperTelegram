import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            switch environment.authState {
            case .ready:
                MainTabView()
            case .unknown:
                LoadingView()
            case .missingCredentials:
                MissingCredentialsView()
            default:
                AuthView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: environment.authState)
        .overlay(alignment: .top) { BannerView() }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ChatListView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 42))
                .foregroundStyle(CasperTheme.ghostGradient)
            ProgressView()
            Text("Casper запускается…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct MissingCredentialsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Нужны ключи Telegram")
                    .font(.title2.bold())
                Text("""
                Сборка собрана без api_id и api_hash, поэтому подключиться к Telegram нельзя.

                1. Откройте my.telegram.org → API development tools и создайте приложение.
                2. Добавьте api_id и api_hash в GitHub Secrets как TELEGRAM_API_ID и TELEGRAM_API_HASH.
                3. Запустите сборку заново.

                Подробно: docs/TELEGRAM-API.md в репозитории.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

struct BannerView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        if let text = environment.banner {
            Text(text)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .casperSurface(cornerRadius: 14)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { environment.banner = nil }
                .task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    environment.banner = nil
                }
        }
    }
}
