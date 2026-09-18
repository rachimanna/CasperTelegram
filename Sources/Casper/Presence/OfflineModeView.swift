import SwiftUI

/// «Офлайн» — это уже серверная настройка Telegram: кто видит ваш статус
/// «был(а) в сети». Она меняется методом setUserPrivacySettingRules и,
/// в отличие от «Призрака», действует и когда Casper закрыт.
struct OfflineModeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: CasperSettingsStore

    @State private var isSaving = false
    @State private var savedAt: Date?
    @State private var error: String?

    private var rules: Binding<ShowStatusRules> {
        $settingsStore.settings.privacy.showStatus
    }

    var body: some View {
        List {
            Section {
                Picker("Видят статус", selection: rules.visibility) {
                    ForEach(ShowStatusVisibility.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("«Был(а) в сети»")
            } footer: {
                Text("Это настройка на стороне Telegram, поэтому она работает всегда — даже когда Casper выключен.")
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Label("Применить в Telegram", systemImage: "icloud.and.arrow.up")
                        Spacer()
                        if isSaving { ProgressView() }
                    }
                }
                .disabled(isSaving)

                Button("Загрузить текущие настройки из Telegram") {
                    load()
                }
                .font(.footnote)
            } footer: {
                if let savedAt {
                    Text("Сохранено в \(savedAt.timeStamp).")
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Casper не меняет ваши настройки приватности сам — только по нажатию этой кнопки.")
                }
            }

            Section("Важно понимать") {
                LimitationRow(text: "Если вы скрываете своё «был(а) в сети» от всех, Telegram перестаёт показывать точное время и вам. Это правило самого Telegram, обойти его клиент не может.")
                LimitationRow(text: "Флаг «сейчас в сети» этой настройкой не управляется. Им управляет режим «Призрак» — он просто не сообщает серверу, что вы онлайн.")
                LimitationRow(text: "Casper не может «сделать вас офлайн» на сервере в момент, когда другой ваш клиент Telegram открыт и сообщает, что вы онлайн.")
            }
        }
        .navigationTitle("Офлайн")
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            do {
                try await environment.telegram.setShowStatusRules(settingsStore.settings.privacy.showStatus)
                savedAt = Date()
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func load() {
        Task {
            do {
                let loaded = try await environment.telegram.showStatusRules()
                settingsStore.settings.privacy.showStatus = loaded
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
