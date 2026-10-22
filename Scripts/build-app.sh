#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NotchClaude"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

cd "$ROOT"

echo "▸ Compilando $APP_NAME $VERSION (release, universal)"
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
else
    swift build -c release
    BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
fi

echo "▸ Montando $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "▸ Gerando ícone"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/Scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "▸ Assinando (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "✓ $APP"
