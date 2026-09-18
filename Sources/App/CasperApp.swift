import SwiftUI

@main
struct CasperApp: App {
    @StateObject private var environment = AppEnvironment.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.settingsStore)
                .tint(environment.settings.appearance.accent.color)
                .preferredColorScheme(environment.settings.appearance.mode.colorScheme)
                .task { await environment.start() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // Расписание «Призрака» пересчитываем при возврате в приложение.
                    Task { await environment.applyPresence() }
                }
        }
    }
}
