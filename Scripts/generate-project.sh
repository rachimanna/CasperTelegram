#!/usr/bin/env bash
# Генерирует CasperTelegram.xcodeproj из project.yml.
# Запускается локально на Mac и в GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ XcodeGen не установлен. Установите: brew install xcodegen"
  exit 1
fi

bash Scripts/make-secrets.sh

SPEC="project.yml"
if [ -d "Vendor/TDLibFramework.xcframework" ]; then
  echo "[generate-project] TDLib найден → полный режим (реальный Telegram)."
  cat > project.local.yml <<'YML'
# Автогенерируемый файл (в .gitignore): подключает TDLib, если он скачан.
include:
  - project.yml
targets:
  CasperTelegram:
    dependencies:
      - framework: Vendor/TDLibFramework.xcframework
        embed: true
        codeSign: true
    settings:
      base:
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) CASPER_TDLIB
        # TDLib написан на C++ и использует zlib (Gzip, crc32) —
        # обе библиотеки системные, их нужно подключить явно.
        OTHER_LDFLAGS: $(inherited) -lc++ -lz
YML
  SPEC="project.local.yml"
else
  echo "[generate-project] TDLib не найден → демо-режим (MockTelegramService)."
  echo "                   Чтобы подключить Telegram: bash Scripts/fetch-tdlib.sh"
  rm -f project.local.yml
fi

xcodegen generate --spec "$SPEC" --project .
echo "✅ CasperTelegram.xcodeproj собран из $SPEC"
