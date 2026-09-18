# Архитектура

Этот файл — карта репозитория: что где лежит, как части кода связаны друг с другом
и как добавить новый экран в раздел Casper. Если нужно разобраться, куда писать код,
начинайте отсюда.

## Дерево проекта

```
CasperTelegram/
├── project.yml               # Описание Xcode-проекта для XcodeGen (см. BUILD.md)
├── Scripts/                  # generate-project.sh, fetch-tdlib.sh, make-secrets.sh, ci-test.sh
├── .github/workflows/        # ci.yml, release.yml, tdlib-check.yml
├── Resources/
│   └── Assets.xcassets/      # Иконка, цвет акцента
├── Sources/
│   ├── App/                  # Точка входа, пути к данным, Keychain, AppEnvironment
│   ├── TelegramCore/         # Модели, протокол TelegramService, TDLib-клиент, демо-режим
│   ├── UI/                   # Общий интерфейс: список чатов, чат, авторизация, настройки, тема
│   └── Casper/                # Раздел Casper: Ghost, Presence, DeletedMessages, VoiceChanger,
│                              #   Integrations, Appearance, About, CasperSettings.swift
└── Tests/                    # 5 файлов XCTest
```

### Sources/App

- `CasperApp.swift` — точка входа SwiftUI (`@main`). Создаёт `AppEnvironment`, запускает
  `environment.start()` и пересчитывает присутствие «Призрака» при возврате приложения
  на экран (`scenePhase == .active`).
- `AppPaths.swift` — где на устройстве лежат данные: `Application Support/Casper/tdlib`
  (база TDLib), `casper-archive.sqlite` (архив Casper), `casper-settings.json` (настройки),
  `voice/` (временные записи Voice Changer). Все папки исключены из резервной копии
  (`isExcludedFromBackup`).
- `Keychain.swift` — обёртка над Keychain Services. Хранит ключ шифрования базы TDLib
  (`DatabaseKey`, 32 случайных байта) и ключ AI-интеграции. Ничего секретного не пишется
  ни в `UserDefaults`, ни в обычные файлы.
- `AppEnvironment.swift` — единственный владелец состояния приложения (`ObservableObject`).

### Sources/TelegramCore

- `TelegramService.swift` — протокол, через который всё остальное приложение говорит
  с Telegram (авторизация, чаты, сообщения, присутствие, приватность). Здесь же
  `TelegramServiceFactory`, которая выбирает реализацию.
- `TDLibJSONClient.swift` — тонкая обёртка над C-API tdjson (`td_create_client_id`,
  `td_send`, `td_receive`, `td_execute`), сопоставляет ответы с запросами по `@extra`.
  Целиком обёрнута в `#if canImport(TDLibFramework)`.
- `TDLibTelegramService.swift` — настоящая реализация `TelegramService` на TDLib.
  Тоже обёрнута в `#if canImport(TDLibFramework)`.
- `MockTelegramService.swift` — демо-реализация без единого сетевого запроса: данные
  придуманы, живут в памяти. Код входа — любой номер, код `12345`.
- `TelegramModels.swift` — общие модели (`ChatSummary`, `TelegramMessage`, `AuthState`,
  `ConnectionState`, `ShowStatusRules`, `TelegramEvent`, `TelegramError`), которыми
  пользуются обе реализации и весь остальной код.

### Sources/UI

Общий интерфейс клиента, не зависящий от того, TDLib под ним или демо-режим:
`ChatListView`, `ChatDetailView`, `AuthView`, `SettingsView`, `RootView` (переключает
экран по `authState`: загрузка → нет ключей → авторизация → вкладки чатов/настроек),
`Theme.swift` (`CasperTheme`, общий стиль карточек `casperSurface`).

### Sources/Casper

Раздел «Casper» в настройках, вся его логика работает только через `TelegramService`:
- `CasperHomeView.swift` — экран-меню с карточками разделов.
- `CasperSettings.swift` — единая структура настроек (`CasperSettings`, включает
  `GhostSettings`, `ArchiveSettings`, `VoiceSettings`, `AppearanceSettings`,
  `CasperPrivacySettings`, `AIIntegrationSettings`) и `CasperSettingsStore`
  (`ObservableObject`, читает/пишет `casper-settings.json`, секретов там нет).
- `Ghost/` — `GhostView.swift` (экран), `PresencePolicy.swift` (`PresencePolicy`,
  `GhostSettings` с логикой расписания), `PresenceController.swift` (применяет политику
  к `TelegramService`, помнит уже применённое, отдаёт `current` экранам чата).
- `DeletedMessages/` — `MessageArchive.swift` (SQLite-архив), `DeletedMessagesView.swift`.
- `Presence/OfflineModeView.swift` — экран серверной настройки «был(а) в сети».
- `VoiceChanger/` — `VoiceEffect.swift` (6 эффектов), `VoiceProcessor.swift` (обработка
  через AVAudioEngine), `VoiceRecorder.swift`, `VoiceChangerView.swift`.
- `Integrations/` — `AIIntegrationService.swift` (ключ в Keychain, проверка `GET {baseURL}/models`),
  `IntegrationsView.swift`.
- `Appearance/AppearanceView.swift` — тема, акцент, плотность списка.
- `About/AboutCasperView.swift` — «О Casper»: честные ограничения, лицензии, режим сборки.

### Tests

5 файлов XCTest: `CasperSettingsTests.swift`, `GhostSettingsTests.swift`,
`MessageArchiveTests.swift`, `MockTelegramServiceTests.swift`, `VoiceEffectTests.swift`.
Работают без TDLib, поэтому идут в демо-режиме и в CI.

## Схема: Telegram Core ↔ TelegramService ↔ Casper

```
        ┌────────────────────┐        ┌───────────────────────┐
        │  TDLibTelegramService  │  или  │   MockTelegramService  │
        │  (#if canImport(TDLibFramework)) │ (демо-режим, без TDLib) │
        └───────────┬────────┘        └───────────┬───────────┘
                    │  реализуют протокол           │
                    └───────────────┬───────────────┘
                                    ▼
                         protocol TelegramService
                     (авторизация, чаты, сообщения,
                      присутствие, приватность,
                      onEvent: (TelegramEvent) -> Void)
                                    │
                                    ▼
                             AppEnvironment
                (единственный ObservableObject-владелец состояния)
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              PresenceController  MessageArchive   Sources/UI
              (раздел «Призрак»)  (раздел «Удалённые»)  (чаты, авторизация,
                                                          настройки)
```

Ключевой приём: весь код раздела Casper и весь общий UI работает исключительно
через протокол `TelegramService` и не знает, какая реализация под ним. Файлы
`TDLibJSONClient.swift` и `TDLibTelegramService.swift` целиком обёрнуты в
`#if canImport(TDLibFramework)`. Если TDLib не скачан (`Vendor/TDLibFramework.xcframework`
отсутствует), `TelegramServiceFactory.make()` собирает `MockTelegramService`, и
приложение всё равно запускается на демо-данных — CI остаётся зелёным без единого
сетевого ключа.

## AppEnvironment и поток событий

`AppEnvironment` (`Sources/App/AppEnvironment.swift`) — единственный `ObservableObject`
с состоянием приложения (`AuthState`, `ConnectionState`, список чатов, статистика
и записи архива, баннер с ошибкой). Он:

1. Создаёт `TelegramService` (через `TelegramServiceFactory.make()`) и `PresenceController`
   поверх него, открывает `MessageArchive` (если открытие не удалось — работает без архива
   и показывает `archiveError`).
2. Подписывается на `telegram.onEvent` — единый канал событий `TelegramEvent`:
   `.authState`, `.connection`, `.chatsChanged`, `.newMessage`, `.messagesDeleted`, `.failure`.
   Оба клиента (TDLib и демо) шлют одни и те же случаи `TelegramEvent`, поэтому
   `AppEnvironment` не отличает, откуда пришло событие.
3. На `.authState(.ready)` — применяет политику присутствия, обновляет список чатов,
   чистит архив по сроку хранения.
4. На `.newMessage` — если архив включён и чат не секретный, сохраняет сообщение
   в `MessageArchive`.
5. На `.messagesDeleted` — если `fromCache == false` (то есть это не просто освобождение
   локального кэша TDLib), помечает сообщения удалёнными в архиве и показывает баннер.
6. Слушает `settingsStore.$settings.map(\.ghost)` и при любом изменении настроек
   «Призрака» сразу пересчитывает и применяет политику присутствия.

## Зачем демо-режим

`MockTelegramService` нужен по двум причинам:
1. GitHub Actions собирает и тестирует приложение без TDLib и без ключей — CI остаётся
   зелёным.
2. Можно проверять интерфейс и логику Casper (Призрак, архив), не входя в настоящий
   аккаунт: демо-сервис даже воспроизводит сценарий «пришло сообщение → через 8 секунд
   собеседник его удалил», чтобы можно было увидеть работу архива вживую.

## Как добавить новый экран в раздел Casper

1. Создайте папку `Sources/Casper/ИмяРаздела/` и в ней `ИмяРазделаView.swift`
   (обычный SwiftUI `View`, берите пример по структуре `Ghost/GhostView.swift`).
2. Если разделу нужны настройки — добавьте структуру `Codable & Equatable`
   в `Sources/Casper/CasperSettings.swift` и подключите её как поле в `CasperSettings`.
   Она автоматически сохранится в `casper-settings.json`.
3. Если разделу нужен доступ к Telegram — используйте `environment.telegram`
   (протокол `TelegramService`), а не пишите собственный код TDLib.
4. Добавьте карточку в `CasperHomeView.swift` (`LazyVGrid`) с `NavigationLink`
   на новый экран.
5. Если в разделе есть логика без UI (как `PresencePolicy` для Ghost) — вынесите её
   в отдельный `.swift`-файл того же раздела, чтобы её можно было протестировать
   отдельно от SwiftUI.
6. Добавьте тест в `Tests/` (см. пример `GhostSettingsTests.swift`), особенно если
   логика не тривиальна.
7. Проект пересоберётся сам: `.xcodeproj` не хранится в git, `Sources/` целиком входит
   в таргет через `project.yml` (`sources: - path: Sources`), поэтому новый файл
   подхватится при следующем запуске `Scripts/generate-project.sh`.

## Другие документы

- [Ограничения](LIMITATIONS.md)
- [Работа с iPhone](IPHONE-WORKFLOW.md)
- [Сборка](BUILD.md)
- [Секреты](SECRETS.md)
- [Telegram API](TELEGRAM-API.md)
- [Установка на iPhone](INSTALL-IPHONE.md)
- [Roadmap](ROADMAP.md)
