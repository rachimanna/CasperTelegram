import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject private var settingsStore: CasperSettingsStore

    private var appearance: Binding<AppearanceSettings> {
        $settingsStore.settings.appearance
    }

    var body: some View {
        List {
            Section("Тема") {
                Picker("Тема", selection: appearance.mode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Акцент") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                    ForEach(CasperAccent.allCases) { accent in
                        Button {
                            appearance.accent.wrappedValue = accent
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .opacity(settingsStore.settings.appearance.accent == accent ? 1 : 0)
                                    )
                                Text(accent.title).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Список чатов") {
                Toggle("Компактный вид", isOn: appearance.compactChatList)
                Toggle("Показывать значок Призрака", isOn: appearance.showCasperBadge)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Скругление пузырей: \(Int(settingsStore.settings.appearance.bubbleCornerRadius)) pt")
                        .font(.footnote)
                    Slider(value: appearance.bubbleCornerRadius, in: 6...24, step: 1)
                    previewBubbles
                }
            } header: {
                Text("Сообщения")
            }
        }
        .navigationTitle("Внешний вид")
    }

    private var previewBubbles: some View {
        let radius = CGFloat(settingsStore.settings.appearance.bubbleCornerRadius)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Привет! Как тебе Casper?")
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.quaternary))
            Text("Выглядит родным 👻")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.accentColor))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
