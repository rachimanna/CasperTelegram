import SwiftUI

struct ChatDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: CasperSettingsStore

    let chat: ChatSummary

    @State private var messages: [TelegramMessage] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var showVoiceChanger = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if environment.isGhostActive && settingsStore.settings.ghost.hideReadReceipts {
                ghostNotice
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if isLoading { ProgressView().padding(.top, 24) }
                        ForEach(messages) { message in
                            MessageBubble(message: message,
                                          showSender: chat.isGroup || chat.isChannel)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            composer
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear {
            Task { try? await environment.presence.closeChat(chat.id) }
        }
        .sheet(isPresented: $showVoiceChanger) {
            VoiceChangerView(targetChat: chat)
        }
        .alert("Ошибка", isPresented: Binding(get: { error != nil },
                                              set: { if !$0 { error = nil } })) {
            Button("Понятно") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var ghostNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
            Text("Отметки о прочтении не отправляются")
                .font(.caption)
            Spacer()
            Button("Прочитать") {
                Task {
                    try? await environment.presence.forceMarkRead(chatID: chat.id,
                                                                  messageIDs: messages.map(\.id))
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.indigo.opacity(0.12))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Сообщение", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .casperSurface(cornerRadius: 20)
                .onChange(of: draft) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    Task { try? await environment.presence.sendTypingIfAllowed(chatID: chat.id) }
                }

            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { showVoiceChanger = true } label: {
                    Image(systemName: "mic.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
            } else {
                Button { send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.title3.weight(.bold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func load() async {
        do {
            try await environment.presence.openChat(chat.id)
            messages = try await environment.telegram.messages(chatID: chat.id, limit: 60)
            try await environment.presence.markReadIfAllowed(chatID: chat.id,
                                                             messageIDs: messages.map(\.id))
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task {
            do {
                try await environment.telegram.sendText(text, to: chat.id)
                messages = try await environment.telegram.messages(chatID: chat.id, limit: 60)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct MessageBubble: View {
    @EnvironmentObject private var settingsStore: CasperSettingsStore
    let message: TelegramMessage
    var showSender: Bool

    private var radius: CGFloat {
        CGFloat(settingsStore.settings.appearance.bubbleCornerRadius)
    }

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 48) }

            VStack(alignment: .leading, spacing: 3) {
                if showSender && !message.isOutgoing && !message.senderName.isEmpty {
                    Text(message.senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    if let symbol = message.kind.symbol {
                        Image(systemName: symbol).font(.footnote)
                    }
                    Text(message.displayText)
                        .font(.callout)
                    Text(message.date.timeStamp)
                        .font(.caption2)
                        .foregroundStyle(message.isOutgoing ? .white.opacity(0.75) : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(message.isOutgoing
                          ? AnyShapeStyle(Color.accentColor)
                          : AnyShapeStyle(Color(.secondarySystemFill)))
            )
            .foregroundStyle(message.isOutgoing ? Color.white : Color.primary)

            if !message.isOutgoing { Spacer(minLength: 48) }
        }
    }
}
