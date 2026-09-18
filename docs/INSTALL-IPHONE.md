# Установка на свой iPhone

Как легально поставить Casper на собственный iPhone: сравнение вариантов и
пошаговая настройка рекомендуемого — TestFlight.

## Сравнение вариантов

| Вариант | Стоимость | Удобство с iPhone | Срок действия сборки | Рекомендация |
|---|---|---|---|---|
| **Apple Developer Program → TestFlight** | $99/год | Однократная настройка, дальше обновления ставятся прямо из приложения TestFlight | Пока действует членство в программе | Рекомендуется |
| **Бесплатная подпись (Personal Team)** | Бесплатно | Неудобно: подпись живёт 7 дней, нужна регулярная пересборка, а главное — процесс подписи и установки бесплатным сертификатом требует Mac с кабелем (Xcode ставит приложение через прямое подключение к устройству) | 7 дней | Не подходит для работы «только с iPhone» |
| **Публикация в App Store** | $99/год (та же программа) | Одна кнопка «Установить» из App Store после публикации | Постоянно, пока приложение в App Store | Возможна, но проходит ревью Apple — отдельная история, дольше и с непредсказуемым результатом для стороннего Telegram-клиента |

Почему рекомендуется именно TestFlight: у внутренних тестировщиков (это сам
разработчик, до 100 устройств) сборки не проходят ревью Apple, ставятся сразу
после выгрузки, и вся настройка делается один раз.

## Что нужно для TestFlight

1. Активная подписка **Apple Developer Program** ($99/год,
   [developer.apple.com/programs](https://developer.apple.com/programs/)).
2. Сертификат подписи **Apple Distribution** (.p12) и пароль от него.
3. **Provisioning profile** для Bundle ID `app.casper.telegram`, подписанный тем
   же сертификатом.
4. Ключ **App Store Connect API** (.p8) для автоматической выгрузки из CI.
5. Заполненные GitHub Secrets — полный список и как их получить в [SECRETS.md](SECRETS.md).

## Пошаговая настройка

### 1. Оформить Apple Developer Program

Зарегистрируйтесь на [developer.apple.com/programs](https://developer.apple.com/programs/)
(можно оформить через Safari на iPhone, оплата привязывается к Apple ID). После
одобрения (обычно от нескольких часов до пары дней) в аккаунте появится
Team ID — он же `APPLE_TEAM_ID`.

### 2. Зарегистрировать App ID

1. [developer.apple.com/account](https://developer.apple.com/account) → **Certificates,
   Identifiers & Profiles** → **Identifiers** → **+**.
2. Тип — **App IDs** → **App**.
3. Bundle ID: **Explicit**, значение `app.casper.telegram`.
4. Включите нужные Capabilities (как минимум ничего дополнительного не требуется
   для базовой сборки; при добавлении push-уведомлений на Этапе 5 понадобится
   Push Notifications).
5. Сохраните.

### 3. Получить сертификат Apple Distribution

Обычно сертификат создают в Keychain Access на Mac, но это не обязательно —
запрос на сертификат (CSR) можно создать где угодно через `openssl`:

1. На любом устройстве с `openssl` (например, через сервис-песочницу или временный
   облачный терминал) выполните:
   ```
   openssl genrsa -out distribution.key 2048
   openssl req -new -key distribution.key -out distribution.csr -subj "/CN=Casper Distribution/"
   ```
2. В **Certificates, Identifiers & Profiles → Certificates → +** выберите
   **Apple Distribution**, загрузите `distribution.csr` через Safari на iPhone.
3. Скачайте выданный сертификат (`.cer`) — тоже можно прямо в Safari на iPhone.
4. Соберите `.p12` (сертификат + приватный ключ), например через `openssl` там же,
   где создавали CSR:
   ```
   openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
   openssl pkcs12 -export -inkey distribution.key -in distribution.pem -out distribution.p12 -passout pass:ВАШ_ПАРОЛЬ
   ```
5. Закодируйте `.p12` в base64 и сохраните пароль — понадобятся для
   `IOS_DIST_CERT_P12_BASE64` и `IOS_DIST_CERT_PASSWORD`.

Альтернатива без ручной возни с `openssl`: настроить `fastlane match` на
macOS-раннере GitHub Actions — тогда весь жизненный цикл сертификатов (создание,
хранение, обновление) берёт на себя CI, а с iPhone нужно только один раз задать
секреты для `match`. Это отдельная настройка, в `release.yml` проекта сейчас не
включена.

### 4. Создать Provisioning Profile

1. **Profiles → +** → **App Store Connect** (тип distribution-профиля, подходит
   и для TestFlight).
2. Выберите App ID `app.casper.telegram`, затем созданный сертификат Apple
   Distribution.
3. Дайте профилю понятное имя — это и будет значение `IOS_PROVISIONING_PROFILE_NAME`.
4. Скачайте `.mobileprovision`, закодируйте в base64 —
   `IOS_PROVISIONING_PROFILE_BASE64`.

### 5. Создать ключ App Store Connect API

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Users and
   Access → Keys**.
2. **+** → задайте имя, роль — достаточно **App Manager**.
3. Скачайте `.p8` (доступен для скачивания только один раз), запомните
   **Key ID** и **Issuer ID**.
4. Закодируйте `.p8` в base64 — получите `ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`.

### 6. Добавить всё в GitHub Secrets

Пошагово — в [SECRETS.md](SECRETS.md), раздел «Как добавить секрет в GitHub Secrets
с iPhone». Нужны все восемь секретов подписи и выгрузки плюс `TELEGRAM_API_ID`/
`TELEGRAM_API_HASH` ([TELEGRAM-API.md](TELEGRAM-API.md)), иначе сборка Telegram-ядра
уйдёт в демо-режим.

### 7. Создать приложение в App Store Connect

1. **App Store Connect → My Apps → +** → **New App**.
2. Платформа iOS, имя (например, «Casper»), основной язык, Bundle ID `app.casper.telegram`,
   SKU — любая уникальная строка.
3. Сохраните — карточка приложения нужна, чтобы было куда выгружать сборки
   из Release workflow.

### 8. Запустить сборку и добавить себя тестировщиком

1. Actions → **Release → TestFlight** → **Run workflow** (подробнее в
   [IPHONE-WORKFLOW.md](IPHONE-WORKFLOW.md)).
2. После успешной выгрузки откройте App Store Connect → ваше приложение → вкладка
   **TestFlight** → **Internal Testing** → добавьте себя (владельца аккаунта) как
   внутреннего тестировщика, если ещё не добавлены.
3. На iPhone установите приложение **TestFlight** из App Store.
4. Примите приглашение (письмо или уведомление в TestFlight) и установите Casper.

Дальше каждое обновление — просто новый запуск Release workflow и нажатие
«Обновить» в TestFlight.

## Другие документы

- [Архитектура](ARCHITECTURE.md)
- [Ограничения](LIMITATIONS.md)
- [Работа с iPhone](IPHONE-WORKFLOW.md)
- [Сборка](BUILD.md)
- [Секреты](SECRETS.md)
- [Telegram API](TELEGRAM-API.md)
- [Roadmap](ROADMAP.md)
