import SwiftUI

struct IntegrationsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: CasperSettingsStore

    @State private var keyDraft = ""
    @State private var hasKey = false
    @State private var status: AIIntegrationService.Status = .unknown

    private var integration: Binding<AIIntegrationSettings> {
        $settingsStore.settings.integration
    }

    var body: some View {
        List {
            Section {
                Toggle("Использовать AI-сервис", isOn: integration.isEnabled)
            } header: {
                Text("AI-сервис")
            } footer: {
                Text("Нужен только для расшифровки и перевода голосовых сообщений. Сам Voice Changer работает локально и никакого ключа не требует.")
            }

            if settingsStore.settings.integration.isEnabled {
                Section("Подключение") {
                    TextField("Адрес API", text: integration.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Модель (необязательно)", text: integration.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField(hasKey ? "Ключ сохранён — введите новый, чтобы заменить" : "API Key", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Сохранить ключ") {
                        try? environment.integrations.storeKey(keyDraft)
                        keyDraft = ""
                        hasKey = environment.integrations.hasKey
                    }
                    .disabled(keyDraft.isEmpty)

                    Button {
                        status = .checking
                        Task {
                            status = await environment.integrations.check(
                                baseURL: settingsStore.settings.integration.baseURL
                            )
                        }
                    } label: {
                        HStack {
                            Text("Проверить")
                            Spacer()
                            statusView
                        }
                    }
                    .disabled(!hasKey)

                    if hasKey {
                        Button("Удалить ключ", role: .destructive) {
                            environment.integrations.removeKey()
                            hasKey = false
                        }
                    }
                }
            }

            Section("Безопасность") {
                InfoRow(text: "Ключ хранится в Keychain устройства, а не в файле настроек и не в репозитории.")
                InfoRow(text: "Ключ доступен только после первой разблокировки устройства и не выгружается в резервные копии iCloud.")
                InfoRow(text: "В GitHub-репозитории ключей нет: для сборки используются GitHub Secrets (docs/SECRETS.md).")
            }
        }
        .navigationTitle("Интеграции")
        .onAppear { hasKey = environment.integrations.hasKey }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .unknown:
            EmptyView()
        case .checking:
            ProgressView()
        case .connected(let models):
            Label(models > 0 ? "Подключено · \(models) моделей" : "Подключено", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

struct InfoRow: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.footnote)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
