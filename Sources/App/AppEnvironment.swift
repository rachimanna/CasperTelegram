import Combine
import Foundation

/// Связывает Telegram Core и Casper: слушает события, применяет политику
/// присутствия, ведёт локальный архив. Единственный владелец состояния.
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let telegram: TelegramService
    let settingsStore: CasperSettingsStore
    let presence: PresenceController
    let archive: MessageArchive?
    let integrations = AIIntegrationService()

    @Published var authState: AuthState = .unknown
    @Published var connection: ConnectionState = .connecting
    @Published var chats: [ChatSummary] = []
    @Published var deletedRecords: [MessageArchive.Record] = []
    @Published var archiveStats = MessageArchive.Stats()
    @Published var banner: String?
    @Published var archiveError: String?

    private var cancellables = Set<AnyCancellable>()

    var settings: CasperSettings { settingsStore.settings }
    var isGhostActive: Bool { settings.ghost.isActive() }

    init(telegram: TelegramService = TelegramServiceFactory.make(),
         settingsStore: CasperSettingsStore = CasperSettingsStore()) {
        self.telegram = telegram
        self.settingsStore = settingsStore
        self.presence = PresenceController(service: telegram)

        do {
            archive = try MessageArchive(path: AppPaths.archiveDatabaseURL.path)
        } catch {
            archive = nil
            archiveError = error.localizedDescription
        }

        self.telegram.onEvent = { [weak self] event in
            self?.handle(event)
        }

        // Любое изменение настроек «Призрака» сразу применяется к Telegram.
        settingsStore.$settings
            .map(\.ghost)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { await self?.applyPresence() }
            }
            .store(in: &cancellables)

        refreshArchive()
    }

    // MARK: Жизненный цикл

    func start() async {
        if settings.ghost.enableOnLaunch && !settingsStore.settings.ghost.isEnabled {
            settingsStore.settings.ghost.isEnabled = true
        }
        await telegram.start()
    }

    func applyPresence() async {
        do {
            try await presence.apply(settings.ghost.policy())
        } catch {
            banner = error.localizedDescription
        }
    }

    func refreshChats() async {
        guard authState == .ready else { return }
        do {
            chats = try await telegram.chats(limit: 60)
        } catch {
            banner = error.localizedDescription
        }
    }

    func logOut() async {
        do {
            try await telegram.logOut()
        } catch {
            banner = error.localizedDescription
        }
    }

    // MARK: Архив

    func refreshArchive() {
        guard let archive else { return }
        archiveStats = archive.stats()
        deletedRecords = archive.deletedRecords(limit: 300)
    }

    func purgeArchiveIfNeeded() {
        guard let archive, settings.archive.isEnabled else { return }
        archive.purge(olderThanDays: settings.archive.retentionDays)
        refreshArchive()
    }

    func clearArchive() {
        archive?.clear()
        refreshArchive()
    }

    // MARK: События Telegram

    private func handle(_ event: TelegramEvent) {
        switch event {
        case .authState(let state):
            authState = state
            if state == .ready {
                Task {
                    await applyPresence()
                    await refreshChats()
                    purgeArchiveIfNeeded()
                }
            }

        case .connection(let state):
            connection = state

        case .chatsChanged(let list):
            chats = list

        case .newMessage(let message, let chatTitle, let isSecret):
            store(message, chatTitle: chatTitle, isSecret: isSecret)

        case .messagesDeleted(let chatID, let ids, _, let fromCache):
            handleDeletion(chatID: chatID, messageIDs: ids, fromCache: fromCache)

        case .failure(let text):
            banner = text
        }
    }

    private func store(_ message: TelegramMessage, chatTitle: String, isSecret: Bool) {
        guard let archive, settings.archive.isEnabled else { return }
        // Секретные чаты не архивируются никогда.
        guard !isSecret else { return }
        guard !message.isOutgoing || settings.archive.includeOutgoing else { return }
        archive.store(message, chatTitle: chatTitle)
        archiveStats = archive.stats()
    }

    private func handleDeletion(chatID: Int64, messageIDs: [Int64], fromCache: Bool) {
        // from_cache = TDLib просто освободил локальный кэш.
        // Это не удаление сообщения собеседником, помечать нечего.
        guard !fromCache else { return }
        guard let archive, settings.archive.isEnabled else { return }

        let affected = archive.markDeleted(chatID: chatID, messageIDs: messageIDs)
        guard !affected.isEmpty else { return }

        refreshArchive()
        if settings.archive.notifyOnDeletion {
            let name = affected.first?.chatTitle ?? "Чат"
            banner = affected.count == 1
                ? "«\(name)»: собеседник удалил сообщение — копия в архиве Casper"
                : "«\(name)»: удалено сообщений — \(affected.count). Копии в архиве Casper"
        }
    }
}
