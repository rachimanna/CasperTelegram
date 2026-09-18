# Сторонние компоненты

| Компонент | Назначение | Лицензия |
|---|---|---|
| [TDLib](https://github.com/tdlib/td) | Клиентская библиотека Telegram (MTProto, шифрование, локальная БД) | Boost Software License 1.0 — разрешает коммерческое и закрытое распространение |
| [TDLibFramework](https://github.com/Swiftgram/TDLibFramework) | Готовые XCFramework-сборки TDLib для Apple-платформ | MIT |

Casper **не** является форком официального приложения Telegram для iOS
(оно распространяется под GNU GPL v2). Весь интерфейс Casper написан с нуля
на SwiftUI, а работа с Telegram идёт только через официальный TDLib.

Требования Telegram к сторонним клиентам, которые мы соблюдаем
(https://github.com/TelegramMessenger/Telegram-iOS#creating-your-telegram-application):

1. Собственный `api_id` / `api_hash`, полученный на my.telegram.org.
2. Приложение не называется «Telegram»; в названии, иконке и разделе «О Casper»
   явно указано, что это неофициальный клиент.
3. Не используется стандартный логотип Telegram (белый самолётик на синем круге).
4. Исходный код открыт.
