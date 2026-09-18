# Сборка

Что именно происходит при сборке Casper: шаги CI, как собрать локально на Mac,
если он однажды появится, как подключить или обновить TDLib, чем демо-режим
отличается от полного, и что означают частые ошибки сборки.

## Что делает CI по шагам (`.github/workflows/ci.yml`)

Запускается на каждый push в `main` и на каждый pull request, на раннере `macos-latest`:

1. `actions/checkout@v4` — забирает код.
2. `xcodebuild -version` — печатает версию установленного Xcode (для диагностики).
3. `brew install xcodegen` — ставит XcodeGen.
4. `actions/cache@v4` по ключу `tdlib-1.8.67-d1085f9c-v1` — кэширует папку `Vendor`,
   чтобы не качать TDLib заново на каждом запуске.
5. Если кэша не было — `bash Scripts/fetch-tdlib.sh` (шаг помечен `continue-on-error:
   true`: если скачивание не удалось, сборка не падает, а просто уходит в демо-режим).
6. `bash Scripts/generate-project.sh` — с переменными окружения
   `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` из секретов репозитория (если их нет,
   собирается демо-режим).
7. `bash Scripts/ci-test.sh` — сборка и `xcodebuild test` на первом доступном
   симуляторе iPhone.
8. Выгрузка `build/TestResults.xcresult` как артефакта `test-results`
   (выполняется всегда, даже если сборка упала, — `if: always()`).

## Как собрать локально на Mac (если он однажды появится)

1. Установите Xcode (App Store) и XcodeGen: `brew install xcodegen`.
2. Клонируйте репозиторий.
3. При необходимости настройте `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` в переменных
   окружения (см. ниже «Демо-режим против полного»).
4. Скачайте TDLib (не обязательно для демо-режима): `bash Scripts/fetch-tdlib.sh`.
5. Сгенерируйте проект: `bash Scripts/generate-project.sh` — команда сама вызывает
   `make-secrets.sh` и подключает `Vendor/TDLibFramework.xcframework`, если он на месте.
6. Откройте `CasperTelegram.xcodeproj` в Xcode и запустите обычным способом,
   либо через терминал: `bash Scripts/ci-test.sh` (тесты на симуляторе).

Скрипты запускаются как `bash Scripts/имя.sh` — они приходят из GitHub без флага
исполняемости (+x), поэтому напрямую (`./Scripts/имя.sh`) могут не запуститься.

## Как подключить TDLib

TDLib не компилируется из исходников — используется готовый XCFramework из
[Swiftgram/TDLibFramework](https://github.com/Swiftgram/TDLibFramework) (лицензия MIT).

```
bash Scripts/fetch-tdlib.sh
```

Скрипт скачивает `TDLibFramework.zip` по адресу
`https://github.com/Swiftgram/TDLibFramework/releases/download/${TDLIB_VERSION}/TDLibFramework.zip`
(версия по умолчанию — `1.8.67-d1085f9c`), распаковывает в `Vendor/` и оставляет там
`Vendor/TDLibFramework.xcframework`. Если TDLib уже скачан — скрипт ничего не делает
повторно.

После этого `Scripts/generate-project.sh` увидит `Vendor/TDLibFramework.xcframework`
и подключит его через отдельный `project.local.yml` (в `.gitignore`, генерируется
автоматически): добавляет зависимость на XCFramework, флаг компиляции
`CASPER_TDLIB` и линкер-флаг `-lc++`.

## Демо-режим против полного

| | Демо-режим | Полный режим |
|---|---|---|
| Условие | `Vendor/TDLibFramework.xcframework` отсутствует | TDLib скачан в `Vendor/` |
| Реализация `TelegramService` | `MockTelegramService` | `TDLibTelegramService` |
| Нужны `TELEGRAM_API_ID`/`TELEGRAM_API_HASH` | Нет | Да |
| Сетевые запросы | Нет, всё в памяти | Настоящий Telegram через TDLib |
| Вход | Любой номер, код `12345` | Настоящий номер и код из Telegram |
| Когда используется | CI по умолчанию, разработка интерфейса | Проверка на живом аккаунте, релиз |

Переключение полностью автоматическое — через `#if canImport(TDLibFramework)`
в `TelegramServiceFactory.make()`. Собирать один и тот же код с флагом или без него
не нужно, достаточно наличия/отсутствия `Vendor/TDLibFramework.xcframework`
на момент генерации проекта.

## Как обновить версию TDLib

1. Проверьте новую версию (тег релиза) в
   [Swiftgram/TDLibFramework releases](https://github.com/Swiftgram/TDLibFramework/releases).
2. Обновите значение по умолчанию в `Scripts/fetch-tdlib.sh` (`TDLIB_VERSION`)
   и в `.github/workflows/ci.yml` (`env.TDLIB_VERSION`), а также ключ кэша
   (`tdlib-1.8.67-d1085f9c-v1` → новая версия) — иначе CI продолжит брать старую
   версию из кэша.
3. Перед тем как менять основной workflow, проверьте новую версию через
   `.github/workflows/tdlib-check.yml` (Actions → TDLib check → Run workflow,
   указать версию в поле `tdlib_version`) — он скачивает XCFramework и печатает
   его содержимое и архитектуры без полной сборки.
4. Закоммитьте изменения и дождитесь зелёного CI на `main`.

## Частые ошибки сборки

| Сообщение / симптом | Что значит |
|---|---|
| `❌ XcodeGen не установлен` | Локально на Mac не поставлен XcodeGen: `brew install xcodegen` |
| `[fetch-tdlib] ❌ TDLibFramework.xcframework не найден в архиве` | Скачанный `TDLibFramework.zip` не содержит ожидаемую папку — проверьте `TDLIB_VERSION`/`TDLIB_XCFRAMEWORK_URL` |
| `⚠️ TELEGRAM_API_ID / TELEGRAM_API_HASH не заданы — сборка будет в демо-режиме` | Не строка с ошибкой, а предупреждение из `make-secrets.sh`: сборка пройдёт, но в приложении будет экран «Нужны ключи Telegram» ([TELEGRAM-API.md](TELEGRAM-API.md)) |
| `❌ Не найдено ни одного доступного симулятора iPhone` | На раннере/Mac нет установленных симуляторов iPhone — редкая ситуация на GitHub Actions, на Mac проверьте Xcode → Settings → Platforms |
| Release: `❌ Не заданы GitHub Secrets: ...` | Не хватает одного или нескольких секретов для подписи/выгрузки — см. [SECRETS.md](SECRETS.md), список секретов указан в самом сообщении |
| Ошибка на шаге «Архив» про подпись (`No signing certificate`, `profile doesn't match`) | Не совпадают `APPLE_TEAM_ID`, сертификат (`IOS_DIST_CERT_P12_BASE64`) и provisioning profile (`IOS_PROVISIONING_PROFILE_BASE64`/`_NAME`) — все три должны быть из одного Apple-аккаунта и совпадать по Bundle ID `app.casper.telegram` |
| Ошибка `xcrun altool` про недействительный ключ API | `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8_BASE64` не соответствуют друг другу или ключ отозван в App Store Connect |

## Другие документы

- [Архитектура](ARCHITECTURE.md)
- [Ограничения](LIMITATIONS.md)
- [Работа с iPhone](IPHONE-WORKFLOW.md)
- [Секреты](SECRETS.md)
- [Telegram API](TELEGRAM-API.md)
- [Установка на iPhone](INSTALL-IPHONE.md)
- [Roadmap](ROADMAP.md)
