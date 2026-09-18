# Секреты

Какие секреты нужны проекту, где их взять, как добавить в GitHub Secrets прямо
с iPhone, что нельзя коммитить и что делать, если ключ всё-таки утёк.

## Список секретов

| Секрет | Зачем | Нужен для |
|---|---|---|
| `TELEGRAM_API_ID` | api_id с my.telegram.org | подключение к Telegram |
| `TELEGRAM_API_HASH` | api_hash с my.telegram.org | подключение к Telegram |
| `APPLE_TEAM_ID` | Team ID из Apple Developer | подпись |
| `IOS_DIST_CERT_P12_BASE64` | сертификат Apple Distribution (.p12) в base64 | подпись |
| `IOS_DIST_CERT_PASSWORD` | пароль от .p12 | подпись |
| `IOS_PROVISIONING_PROFILE_BASE64` | provisioning profile в base64 | подпись |
| `IOS_PROVISIONING_PROFILE_NAME` | имя профиля | подпись |
| `ASC_KEY_ID` | ID ключа App Store Connect API | выгрузка в TestFlight |
| `ASC_ISSUER_ID` | Issuer ID App Store Connect API | выгрузка в TestFlight |
| `ASC_KEY_P8_BASE64` | ключ App Store Connect API (.p8) в base64 | выгрузка в TestFlight |

`TELEGRAM_API_ID`/`TELEGRAM_API_HASH` нужны, чтобы CI и Release собирали приложение
в полном режиме (см. [TELEGRAM-API.md](TELEGRAM-API.md)). Остальные восемь секретов
использует только `.github/workflows/release.yml` для подписи и выгрузки в TestFlight
(см. [INSTALL-IPHONE.md](INSTALL-IPHONE.md)).

## Где взять каждый секрет

- **`TELEGRAM_API_ID` / `TELEGRAM_API_HASH`** — my.telegram.org → API development tools,
  пошагово в [TELEGRAM-API.md](TELEGRAM-API.md).
- **`APPLE_TEAM_ID`** — [developer.apple.com/account](https://developer.apple.com/account) →
  Membership details → Team ID.
- **`IOS_DIST_CERT_P12_BASE64` / `IOS_DIST_CERT_PASSWORD`** — сертификат Apple
  Distribution: получить его и подготовить .p12 подробно описано в
  [INSTALL-IPHONE.md](INSTALL-IPHONE.md) (можно целиком с iPhone через openssl и Safari,
  либо через `fastlane match` на macOS-раннере). `IOS_DIST_CERT_PASSWORD` — пароль,
  который вы сами задаёте при экспорте .p12.
- **`IOS_PROVISIONING_PROFILE_BASE64` / `IOS_PROVISIONING_PROFILE_NAME`** — provisioning
  profile создаётся в Apple Developer после того, как сертификат готов; `_NAME` — точное
  имя профиля, как оно указано в Apple Developer (используется в
  `PROVISIONING_PROFILE_SPECIFIER` при сборке).
- **`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8_BASE64`** — App Store Connect →
  Users and Access → Keys → создать ключ с доступом App Manager (или менее широким,
  достаточным для загрузки сборок); Key ID и Issuer ID показаны на этой же странице,
  файл `.p8` скачивается один раз при создании ключа.

Значения в base64 (`_BASE64`) получаются командой `base64 -i файл.p12 | pbcopy`
на Mac, либо любым онлайн/офлайн base64-кодировщиком на iPhone (например, через
приложение «Команды»/Shortcuts или Working Copy, если файл туда попал).

## Как добавить секрет в GitHub Secrets с iPhone

1. Откройте репозиторий `rachimanna/CasperTelegram` в Safari или GitHub Mobile.
2. Перейдите в **Settings** репозитория (не аккаунта).
3. **Secrets and variables → Actions**.
4. Нажмите **New repository secret**.
5. В поле «Name» впишите точное имя секрета из таблицы выше (заглавными буквами,
   с подчёркиваниями, без пробелов).
6. В поле «Secret» вставьте значение (для файлов — уже закодированное в base64,
   одной строкой).
7. Нажмите **Add secret**.
8. Повторите для каждого нужного секрета.

Значение секрета после сохранения нигде не показывается повторно — GitHub скрывает
его даже от владельца репозитория. Если нужно изменить значение, пересоздайте
секрет заново с тем же именем.

## Что нельзя коммитить

Уже исключено `.gitignore`, но важно понимать, почему — не пытайтесь добавлять эти
файлы в git вручную:

- `*.p12`, `*.cer`, `*.certSigningRequest`, `*.mobileprovision`, `*.p8` — сертификаты
  и ключи подписи/API.
- `.env`, `.env.*`, `secrets.json` — если вдруг заведёте локальный файл с ключами.
- `Sources/App/Secrets.generated.swift` — генерируется `Scripts/make-secrets.sh`
  из `TELEGRAM_API_ID`/`TELEGRAM_API_HASH`, содержит их в виде исходного кода.
- `Vendor/` — сторонний бинарник TDLib, скачивается заново каждый раз.
- `*.xcodeproj`, `project.local.yml` — генерируются, а `project.local.yml` к тому же
  может содержать пути к `Vendor/`.
- `*.ipa`, `*.xcarchive`, `*.app.dSYM.zip` — собранные артефакты, не исходный код.

## Что делать при утечке ключа

1. **`TELEGRAM_API_HASH`/`TELEGRAM_API_ID` утекли** — зайдите на my.telegram.org →
   API development tools и отзовите/пересоздайте приложение (или обратитесь
   в поддержку Telegram, если самостоятельно отозвать нельзя для конкретного случая);
   получите новую пару `api_id`/`api_hash` и обновите оба секрета в GitHub.
2. **Сертификат подписи (`IOS_DIST_CERT_P12_BASE64`) утёк** — в Apple Developer →
   Certificates отзовите (Revoke) скомпрометированный сертификат Apple Distribution,
   создайте новый, пересоберите provisioning profile под него и обновите
   `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`,
   `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_PROVISIONING_PROFILE_NAME`.
3. **Ключ App Store Connect API (`ASC_KEY_P8_BASE64`) утёк** — в App Store Connect →
   Users and Access → Keys удалите скомпрометированный ключ, создайте новый и
   обновите `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`.
4. В любом случае после замены секрета запустите Release заново, чтобы убедиться,
   что новая сборка проходит подпись и выгрузку.

## Другие документы

- [Архитектура](ARCHITECTURE.md)
- [Ограничения](LIMITATIONS.md)
- [Работа с iPhone](IPHONE-WORKFLOW.md)
- [Сборка](BUILD.md)
- [Telegram API](TELEGRAM-API.md)
- [Установка на iPhone](INSTALL-IPHONE.md)
- [Roadmap](ROADMAP.md)
