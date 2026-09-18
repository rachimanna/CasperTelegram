#!/usr/bin/env bash
# Генерирует Sources/App/Secrets.generated.swift из переменных окружения.
# Файл добавлен в .gitignore и НИКОГДА не попадает в репозиторий.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="Sources/App/Secrets.generated.swift"
API_ID="${TELEGRAM_API_ID:-0}"
API_HASH="${TELEGRAM_API_HASH:-}"

cat > "$OUT" <<SWIFT
// ВНИМАНИЕ: файл создаётся автоматически скриптом Scripts/make-secrets.sh.
// Не редактировать и не коммитить.
import Foundation

enum TelegramCredentials {
    static let apiID: Int32 = ${API_ID}
    static let apiHash: String = "${API_HASH}"

    static var isConfigured: Bool { apiID != 0 && !apiHash.isEmpty }
}
SWIFT

if [ "$API_ID" = "0" ] || [ -z "$API_HASH" ]; then
  echo "[make-secrets] ⚠️  TELEGRAM_API_ID / TELEGRAM_API_HASH не заданы — сборка будет в демо-режиме."
else
  echo "[make-secrets] ✅ ключи Telegram подставлены (api_id=${API_ID})."
fi
