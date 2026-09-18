# Telegram API

Как получить свой `api_id`/`api_hash` на my.telegram.org с iPhone, какие требования
Telegram предъявляет к сторонним клиентам и какие методы TDLib использует Casper.

## Получить api_id и api_hash с iPhone

1. Откройте в Safari [my.telegram.org](https://my.telegram.org).
2. Войдите под своим номером телефона Telegram (придёт код в приложение Telegram).
3. Откройте раздел **API development tools**.
4. Заполните форму создания приложения:
   - **App title** — например, «Casper».
   - **Short name** — например, «casper».
   - **Platform** — выберите «iOS» (или «Other», если такого пункта нет).
   - Остальные поля (URL, описание) можно оставить пустыми или заполнить произвольно.
5. Отправьте форму. Появятся два значения: **App api_id** (число) и **App api_hash**
   (строка из букв и цифр). Это и есть искомые `TELEGRAM_API_ID` и `TELEGRAM_API_HASH`.
6. Добавьте оба значения в GitHub Secrets — пошагово в [SECRETS.md](SECRETS.md).

`api_id`/`api_hash` привязаны к вашему Telegram-аккаунту, но их назначение —
идентифицировать приложение (Casper), а не аккаунт: с ними можно входить с
любого номера телефона.

## Требования Telegram к сторонним клиентам

Источники: [core.telegram.org/api/obtaining_api_id](https://core.telegram.org/api/obtaining_api_id)
и README проекта Telegram-iOS. Casper их соблюдает:

1. Используется собственный `api_id`/`api_hash`, полученный на my.telegram.org
   (не чужой и не «общий» ключ).
2. Приложение не называется «Telegram» без явного указания, что оно неофициальное:
   имя на устройстве — «Casper», в разделе «О Casper» прямо написано, что это
   неофициальный клиент, не связанный с Telegram Messenger Inc.
3. Не используется стандартный логотип Telegram (белый самолётик на синем круге).
4. Исходный код проекта открыт (репозиторий `rachimanna/CasperTelegram`, MIT).
5. Сторонний клиент не должен регистрировать новые аккаунты — Casper делает только
   вход. Если номер ещё не зарегистрирован в Telegram (`authorizationStateWaitRegistration`),
   приложение прямо говорит: регистрацию нужно пройти в официальном приложении.

## Методы TDLib, которые использует Casper

### Запуск и авторизация

| Метод / опция | Назначение |
|---|---|
| `setLogVerbosityLevel` | Снижает уровень логов TDLib при старте |
| `getOption("version")` | «Будит» клиента, чтобы TDLib начал присылать `updateAuthorizationState` |
| `setTdlibParameters` | Передаёт `api_id`, `api_hash`, пути к базе, ключ шифрования и параметр `use_secret_chats: false` |
| `checkDatabaseEncryptionKey` | На случай `authorizationStateWaitEncryptionKey` (старые версии TDLib, на 1.8.6+ обычно не вызывается) |
| `setAuthenticationPhoneNumber` | Отправка номера телефона |
| `checkAuthenticationCode` | Проверка кода из SMS/Telegram |
| `checkAuthenticationPassword` | Проверка облачного пароля (двухфакторная защита) |
| `logOut` | Выход из аккаунта |

### Чаты и сообщения

| Метод | Назначение |
|---|---|
| `loadChats` (список `chatListMain`) | Подгрузка списка чатов |
| `getChatHistory` | История сообщений конкретного чата |
| `sendMessage` с `inputMessageText` | Отправка текстового сообщения |
| `sendMessage` с `inputMessageVoiceNote` | Отправка голосового (пока не используется как основной путь — см. [LIMITATIONS.md](LIMITATIONS.md), Voice Changer) |
| `sendMessage` с `inputMessageAudio` | Отправка аудиофайла (текущий способ отправки обработанного голоса) |
| `getUser` | Получение имени отправителя, если его ещё нет в кэше |

### Присутствие (раздел «Призрак»)

| Метод / опция | Назначение |
|---|---|
| `setOption("online", ...)` | Сообщает серверу «я в сети» / не сообщает |
| `openChat` / `closeChat` | Открытие/закрытие чата в TDLib (нужно для подгрузки истории) |
| `viewMessages` | Отметка «прочитано» |
| `sendChatAction` с `chatActionTyping` | Индикатор «печатает…» |

### Приватность (раздел «Офлайн»)

| Метод | Назначение |
|---|---|
| `setUserPrivacySettingRules` (`userPrivacySettingShowStatus`) | Кому виден статус «был(а) в сети»: правила `userPrivacySettingRuleAllowAll` / `AllowContacts` / `RestrictAll` / `AllowUsers` / `RestrictUsers` |
| `getUserPrivacySettingRules` | Чтение текущих правил |

### Обновления, которые слушает Casper

| Обновление | Назначение |
|---|---|
| `updateAuthorizationState` | Состояние авторизации |
| `updateConnectionState` | Состояние соединения с серверами Telegram |
| `updateUser` | Данные пользователя (для имён отправителей) |
| `updateNewChat`, `updateChatLastMessage`, `updateChatPosition`, `updateChatTitle`, `updateChatReadInbox` | Обновления списка чатов |
| `updateNewMessage` | Новое сообщение |
| `updateDeleteMessages` | Удаление сообщений (раздел «Удалённые сообщения», см. [LIMITATIONS.md](LIMITATIONS.md)) |

## Ссылки на документацию

- [core.telegram.org/api/obtaining_api_id](https://core.telegram.org/api/obtaining_api_id) —
  как получить api_id/api_hash и требования к сторонним приложениям.
- [github.com/tdlib/td](https://github.com/tdlib/td) — официальная библиотека TDLib.
- [github.com/Swiftgram/TDLibFramework](https://github.com/Swiftgram/TDLibFramework) —
  готовые XCFramework-сборки TDLib для Apple-платформ, которые использует Casper.
- [core.telegram.org/tdlib/docs](https://core.telegram.org/tdlib/docs) — справочник
  по методам и объектам TDLib (полезно, если добавляете новый метод в
  `TDLibTelegramService`).

## Другие документы

- [Архитектура](ARCHITECTURE.md)
- [Ограничения](LIMITATIONS.md)
- [Работа с iPhone](IPHONE-WORKFLOW.md)
- [Сборка](BUILD.md)
- [Секреты](SECRETS.md)
- [Установка на iPhone](INSTALL-IPHONE.md)
- [Roadmap](ROADMAP.md)
