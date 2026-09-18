import SwiftUI

struct AboutCasperView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("CASPER")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .tracking(5)
                        .foregroundStyle(CasperTheme.ghostGradient)
                    Text("Your Telegram. Your rules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Версия \(AppInfo.version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Что это такое") {
                Text("Casper — неофициальный клиент Telegram. Приложение не связано с Telegram Messenger Inc. и работает через официальную библиотеку TDLib, то есть пользуется только теми возможностями, которые Telegram открывает любому стороннему клиенту.")
                    .font(.footnote)
            }

            Section("Честно о возможностях") {
                InfoRow(text: "«Призрак» не обманывает сервер: клиент просто не отправляет сигналы «в сети», «прочитано» и «печатает».")
                InfoRow(text: "Архив удалённых работает только с сообщениями, которые приложение уже получило. Достать с сервера удалённое невозможно.")
                InfoRow(text: "Voice Changer считает звук на устройстве. Внешние сервисы не нужны.")
            }

            Section("Лицензии") {
                LabeledContent("Casper", value: "MIT")
                LabeledContent("TDLib", value: "Boost 1.0")
                LabeledContent("TDLibFramework", value: "MIT")
                Text("Telegram — торговая марка Telegram Messenger Inc.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section("Режим сборки") {
                LabeledContent("Telegram-ядро", value: environment.telegram.isDemo ? "Демо (TDLib не подключён)" : "TDLib")
            }
        }
        .navigationTitle("О Casper")
    }
}
