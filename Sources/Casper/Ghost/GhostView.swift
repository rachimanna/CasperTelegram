import SwiftUI

struct GhostView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: CasperSettingsStore

    private var ghost: Binding<GhostSettings> {
        $settingsStore.settings.ghost
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: ghost.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Призрак")
                        Text(environment.isGhostActive ? "Активен" : "Выключен")
                            .font(.caption)
                            .foregroundStyle(environment.isGhostActive ? Color.green : Color.secondary)
                    }
                }
            } footer: {
                Text("Сервер Telegram узнаёт о вашей активности только из запросов клиента. Призрак просто не отправляет эти запросы — никакого обмана сервера здесь нет.")
            }

            Section("Что скрывать") {
                Toggle("Онлайн-статус", isOn: ghost.hideOnlineStatus)
                Toggle("Отметки о прочтении", isOn: ghost.hideReadReceipts)
                Toggle("Индикатор «печатает…»", isOn: ghost.hideTypingIndicator)
            }

            Section {
                Toggle("Включать при запуске", isOn: ghost.enableOnLaunch)
                Toggle("По расписанию", isOn: ghost.scheduleEnabled)
                if settingsStore.settings.ghost.scheduleEnabled {
                    TimeRow(title: "Начало", minutes: ghost.scheduleStartMinutes)
                    TimeRow(title: "Конец", minutes: ghost.scheduleEndMinutes)
                }
            } header: {
                Text("Автоматически")
            } footer: {
                Text("Расписание применяется при запуске приложения и при возврате в него. Пока Casper закрыт, вы и так офлайн: статус «в сети» существует только пока его отправляет работающий клиент.")
            }

            Section("Чего Telegram не позволяет") {
                LimitationRow(text: "Скрывать онлайн-статус от отдельных людей — флаг «в сети» один для всех. Точечные исключения возможны только для «был(а) в сети» в разделе «Офлайн».")
                LimitationRow(text: "Быть онлайн для одних и офлайн для других одновременно.")
                LimitationRow(text: "Видеть, кто заходил в ваш профиль: такого метода в API нет ни у одного клиента.")
            }
        }
        .navigationTitle("Призрак")
    }
}

struct TimeRow: View {
    var title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: dateBinding, displayedComponents: .hourAndMinute)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes / 60 % 24,
                                      minute: minutes % 60,
                                      second: 0,
                                      of: Date()) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}

struct LimitationRow: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red.opacity(0.7))
                .font(.footnote)
                .padding(.top, 2)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
