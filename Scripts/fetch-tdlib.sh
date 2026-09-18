#!/usr/bin/env bash
# Скачивает готовый TDLib XCFramework в папку Vendor/.
# TDLib — официальная библиотека Telegram (Boost Software License 1.0).
# Готовые сборки для Apple берём из Swiftgram/TDLibFramework (MIT).
set -euo pipefail
cd "$(dirname "$0")/.."

TDLIB_VERSION="${TDLIB_VERSION:-1.8.67-d1085f9c}"
URL="${TDLIB_XCFRAMEWORK_URL:-https://github.com/Swiftgram/TDLibFramework/releases/download/${TDLIB_VERSION}/TDLibFramework.zip}"

if [ -d "Vendor/TDLibFramework.xcframework" ]; then
  echo "[fetch-tdlib] TDLib уже на месте: Vendor/TDLibFramework.xcframework"
  exit 0
fi

mkdir -p Vendor
echo "[fetch-tdlib] Скачиваю $URL"
curl -fL --retry 3 "$URL" -o Vendor/tdlib.zip
unzip -oq Vendor/tdlib.zip -d Vendor/
rm -f Vendor/tdlib.zip

# Архив может содержать вложенную папку — поднимаем xcframework в корень Vendor/
FOUND="$(find Vendor -maxdepth 3 -name 'TDLibFramework.xcframework' -print -quit || true)"
if [ -z "$FOUND" ]; then
  echo "[fetch-tdlib] ❌ TDLibFramework.xcframework не найден в архиве. Содержимое Vendor/:"
  find Vendor -maxdepth 2
  exit 1
fi
if [ "$FOUND" != "Vendor/TDLibFramework.xcframework" ]; then
  mv "$FOUND" Vendor/TDLibFramework.xcframework
fi

echo "[fetch-tdlib] ✅ Готово: Vendor/TDLibFramework.xcframework (TDLib $TDLIB_VERSION)"
