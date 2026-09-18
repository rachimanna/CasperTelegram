import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var query = ""

    private var filtered: [ChatSummary] {
        guard !query.isEmpty else { return environment.chats }
        return environment.chats.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { chat in
                    NavigationLink(value: chat.id) {
                        ChatRowView(chat: chat)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: Int64.self) { chatID in
                if let chat = environment.chats.first(where: { $0.id == chatID }) {
                    ChatDetailView(chat: chat)
                } else {
                    Text("Чат недоступен")
                }
            }
            .searchable(text: $query, prompt: "Поиск по чатам")
            .refreshable { await environment.refreshChats() }
            .overlay { if filtered.isEmpty { emptyState } }
            .navigationTitle(environment.connection.isBusy ? environment.connection.title : "Чаты")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if environment.isGhostActive { GhostBadge() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Чаты загружаются…" : "Ничего не найдено")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct ChatRowView: View {
    @EnvironmentObject private var settingsStore: CasperSettingsStore
    let chat: ChatSummary

    private var compact: Bool { settingsStore.settings.appearance.compactChatList }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initials: chat.initials, colorIndex: chat.colorIndex, size: compact ? 42 : 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if chat.isChannel {
                        Image(systemName: "megaphone.fill").font(.caption2).foregroundStyle(.secondary)
                    } else if chat.isGroup {
                        Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(chat.title)
                        .font(compact ? .callout.weight(.semibold) : .body.weight(.semibold))
                        .lineLimit(1)
                    if chat.isMuted {
                        Image(systemName: "speaker.slash.fill").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Text(chat.preview.isEmpty ? " " : chat.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                Text(chat.date == .distantPast ? "" : chat.date.chatListStamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(chat.isMuted ? Color.secondary : Color.accentColor))
                }
            }
        }
        .padding(.vertical, 2)
    }
}
