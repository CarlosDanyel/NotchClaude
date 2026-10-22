#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NotchClaude"
VERSION="${VERSION:-1.0.0}"
APP="$ROOT/build/$APP_NAME.app"
DIST="$ROOT/dist"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGING="$ROOT/build/dmg"

[ -d "$APP" ] || VERSION="$VERSION" "$ROOT/Scripts/build-app.sh"

echo "▸ Preparando instalador"
rm -rf "$STAGING"
mkdir -p "$STAGING" "$DIST"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/README.md" "$STAGING/LEIA-ME.md"

echo "▸ Criando $DMG"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGING"

echo "✓ $DMG"
