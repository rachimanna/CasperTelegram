# Roadmap

Восемь этапов проекта: что уже сделано, что дальше, с чек-листами по каждому.

## 1. Основа — сделано

- [x] Репозиторий, структура папок (`App`, `TelegramCore`, `UI`, `Casper`, `Tests`).
- [x] `.xcodeproj` не хранится в git, проект генерируется XcodeGen из `project.yml`.
- [x] Архитектура: `TelegramService` как единая граница между Telegram Core и Casper.
- [x] CI на GitHub Actions (`ci.yml`): сборка и тесты на симуляторе при каждом push/PR.
- [x] Демо-режим (`MockTelegramService`) — приложение и CI работают без TDLib.
- [x] 5 файлов тестов XCTest.

## 2. Telegram — код написан, не проверен на живом аккаунте

- [x] `TDLibJSONClient` — обёртка над tdjson (client-id интерфейс).
- [x] `TDLibTelegramService` — авторизация, чаты, история, отправка текста,
      присутствие, приватность «был(а) в сети».
- [ ] Получить `api_id`/`api_hash` на my.telegram.org ([TELEGRAM-API.md](TELEGRAM-API.md)).
- [ ] Добавить `TELEGRAM_API_ID`/`TELEGRAM_API_HASH` в GitHub Secrets ([SECRETS.md](SECRETS.md)).
- [ ] Первая сборка с реальным TDLib и вход на живой аккаунт.
- [ ] Проверить работу авторизации, списка чатов, истории, отправки сообщений
      на реальных данных.

## 3. Интерфейс — базовое есть, многое впереди

- [x] Список чатов, экран чата с пузырями сообщений.
- [x] Экран авторизации (телефон → код → пароль, с учётом демо-режима).
- [x] Настройки (общие + раздел Casper).
- [ ] Аватары из Telegram (сейчас — инициалы-заглушки).
- [ ] Медиа и вложения (фото, видео, файлы — сейчас только текст и превью-подписи).
- [ ] Пересылка сообщений.
- [ ] Ответы на сообщения (reply).
- [ ] Реакции.
- [ ] Поиск по сообщениям.

## 4. Casper — раздел сделан

- [x] Призрак (`GhostView`, `PresencePolicy`, `PresenceController`).
- [x] Удалённые сообщения (`MessageArchive`, `DeletedMessagesView`).
- [x] Офлайн (`OfflineModeView`, правила «был(а) в сети»).
- [x] Voice Changer (`VoiceProcessor`, `VoiceEffect`, `VoiceRecorder`, `VoiceChangerView`).
- [x] Интеграции (`AIIntegrationService`, `IntegrationsView`).
- [x] Внешний вид (`AppearanceView`).
- [x] О Casper (`AboutCasperView`).

## 5. Функции

- [ ] Кодирование голосовых в Opus/OGG (подключить libopus, написать запись
      Ogg-контейнера) — чтобы отправлять настоящие голосовые сообщения
      (`inputMessageVoiceNote`) вместо аудиофайлов. Подробности —
      [LIMITATIONS.md](LIMITATIONS.md), раздел Voice Changer.
- [ ] Точечные исключения приватности (список пользователей для
      `userPrivacySettingRuleAllowUsers`/`RestrictUsers` в интерфейсе раздела «Офлайн»).
- [ ] Push-уведомления через TDLib (регистрация устройства, обработка входящих push).

## 6. Полировка

- [ ] Анимации переходов между экранами.
- [ ] Иконка приложения (сейчас плейсхолдер в `Assets.xcassets`).
- [ ] Эффект «стекла» iOS 26 — уже подготовлена условная компиляция
      (`#if compiler(>=6.2)` + `if #available(iOS 26.0, *)`, иначе `.ultraThinMaterial`),
      но требует нового Xcode для сборки, чтобы включиться реально.
- [ ] Оптимизация списков (список чатов, история сообщений) для больших объёмов данных.

## 7. Тестирование

- [ ] Проверка на разных моделях iPhone.
- [ ] Проверка на разных версиях iOS (минимум — iOS 18.0, целевая — актуальная).

## 8. Сборка

- [x] Скрипты `generate-project.sh`, `fetch-tdlib.sh`, `make-secrets.sh`, `ci-test.sh`.
- [x] Workflow `release.yml` — подпись, экспорт IPA, выгрузка в TestFlight
      (номер сборки = номер запуска workflow).
- [ ] Пройти полную настройку Apple Developer Program + TestFlight
      ([INSTALL-IPHONE.md](INSTALL-IPHONE.md)) и один раз получить успешный релиз.
- [ ] Автоматический релиз при тегировании версии (сейчас запуск только вручную,
      `workflow_dispatch`).

## Другие документы

- [Архитектура](ARCHITECTURE.md)
- [Ограничения](LIMITATIONS.md)
- [Работа с iPhone](IPHONE-WORKFLOW.md)
- [Сборка](BUILD.md)
- [Секреты](SECRETS.md)
- [Telegram API](TELEGRAM-API.md)
- [Установка на iPhone](INSTALL-IPHONE.md)
