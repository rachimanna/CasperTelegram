import SwiftUI

struct DeletedMessagesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: CasperSettingsStore
    @State private var showClearConfirmation = false

    private var archive: Binding<ArchiveSettings> {
        $settingsStore.settings.archive
    }

    var body: some View {
        List {
            Section {
                Toggle("Хранить локальные копии", isOn: archive.isEnabled)
                if settingsStore.settings.archive.isEnabled {
                    Toggle("Сообщать об удалении", isOn: archive.notifyOnDeletion)
                    Toggle("Хранить и мои сообщения", isOn: archive.includeOutgoing)
                    Picker("Хранить", selection: archive.retentionDays) {
                        Text("1 день").tag(1)
                        Text("3 дня").tag(3)
                        Text("7 дней").tag(7)
                        Text("30 дней").tag(30)
                    }
                }
            } header: {
                Text("Архив на устройстве")
            } footer: {
                Text("Casper сохраняет только те сообщения, которые приложение уже получило обычным путём, и помечает их, когда Telegram сообщает об удалении. Секретные чаты не сохраняются никогда.")
            }

            if let error = environment.archiveError {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }

            Section("Статистика") {
                LabeledContent("Сохранено", value: "\(environment.archiveStats.stored)")
                LabeledContent("Помечено удалёнными", value: "\(environment.archiveStats.deleted)")
            }

            if environment.deletedRecords.isEmpty {
                Section {
                    Text(settingsStore.settings.archive.isEnabled
                         ? "Пока ничего не удаляли. Как только собеседник удалит полученное сообщение, оно появится здесь."
                         : "Функция выключена. Включите её выше, чтобы Casper начал вести локальный архив.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Удалённые") {
                    ForEach(environment.deletedRecords) { record in
                        DeletedRecordRow(record: record)
                            .swipeActions {
                                Button(role: .destructive) {
                                    environment.archive?.removeRecord(chatID: record.chatID,
                                                                      messageID: record.messageID)
                                    environment.refreshArchive()
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            Section {
                Button(role: .destructive) { showClearConfirmation = true } label: {
                    Label("Очистить архив", systemImage: "trash")
                }
            } footer: {
                Text("Чего Casper принципиально не делает: не запрашивает у сервера сообщения, которых не получал, и не восстанавливает удалённое за время, пока приложение было закрыто.")
            }

            Section("Ограничения") {
                LimitationRow(text: "Сообщение, удалённое до того, как Casper его получил, восстановить невозможно — его просто не существует на устройстве.")
                LimitationRow(text: "iOS усыпляет приложения, поэтому часть удалений произойдёт, пока Casper не работает. Это не ошибка, а поведение системы.")
                LimitationRow(text: "Исчезающие сообщения и секретные чаты не архивируются осознанно.")
            }
        }
        .navigationTitle("Удалённые сообщения")
        .onAppear { environment.refreshArchive() }
        .confirmationDialog("Удалить все локальные копии?",
                            isPresented: $showClearConfirmation,
                            titleVisibility: .visible) {
            Button("Очистить", role: .destructive) { environment.clearArchive() }
            Button("Отмена", role: .cancel) {}
        }
    }
}

struct DeletedRecordRow: View {
    let record: MessageArchive.Record

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.chatTitle.isEmpty ? "Чат" : record.chatTitle)
                    .font(.footnote.weight(.semibold))
                if !record.sender.isEmpty {
                    Text("· \(record.sender)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "trash.fill")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.7))
            }
            Text(record.text.isEmpty ? record.kind.placeholder : record.text)
                .font(.callout)
            HStack(spacing: 8) {
                Text("Отправлено \(record.date.fullStamp)")
                if let deletedAt = record.deletedAt {
                    Text("· удалено \(deletedAt.timeStamp)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
