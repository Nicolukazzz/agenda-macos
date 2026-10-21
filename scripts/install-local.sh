#!/bin/zsh
# Build Agenda in Release and install it as /Applications/Agenda.app.
# Ad-hoc signed and without hardened runtime: this is a personal, local-only app.
set -euo pipefail
cd "$(dirname "$0")/.."

(cd AgendaCore && swift test 2>&1 | tail -1)

PRODUCT="build/Build/Products/Release/Agenda.app"
xcodebuild -project Planificador.xcodeproj -scheme Planificador -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ENABLE_HARDENED_RUNTIME=NO build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

[[ -d "$PRODUCT" ]] || { echo "Build product not found: $PRODUCT"; exit 1; }

osascript -e 'tell application id "com.nicolas.agenda" to quit' 2>/dev/null || true
sleep 1
rm -rf "/Applications/Agenda.app"
ditto "$PRODUCT" "/Applications/Agenda.app"
rm -rf "$PRODUCT"
open "/Applications/Agenda.app"
echo "Installed /Applications/Agenda.app"
