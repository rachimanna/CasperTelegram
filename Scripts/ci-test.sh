#!/usr/bin/env bash
# Сборка и запуск тестов на первом доступном симуляторе iPhone.
# Модель симулятора не зашита жёстко, поэтому скрипт не ломается
# при обновлении образов GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")/.."

UDID="$(xcrun simctl list devices available -j \
  | python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];c=[x for k in d for x in d[k] if x["name"].startswith("iPhone")];print(c[-1]["udid"] if c else "")')"

if [ -z "$UDID" ]; then
  echo "❌ Не найдено ни одного доступного симулятора iPhone."
  xcrun simctl list devices available
  exit 1
fi

echo "▶️  Симулятор: $UDID"
xcodebuild test \
  -project CasperTelegram.xcodeproj \
  -scheme CasperTelegram \
  -destination "id=$UDID" \
  -resultBundlePath build/TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
echo "✅ Сборка и тесты прошли."
