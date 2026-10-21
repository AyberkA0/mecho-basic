#!/bin/zsh
# Mecho Basic.app'i derler. `./build.sh install` ile ~/Applications'a kurup başlatır.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Mecho Basic.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 Sources/main.swift -o "$APP/Contents/MacOS/MechoBasic"
codesign --force --sign - "$APP"
echo "Derlendi: $APP"

if [[ "${1:-}" == "install" ]]; then
  DEST="$HOME/Applications/Mecho Basic.app"
  pkill -x MechoBasic 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Kuruldu ve başlatıldı: $DEST"
fi
