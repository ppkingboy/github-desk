#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="GitHub Desk"
EXECUTABLE_NAME="GitHubDesk"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

cd "$ROOT_DIR"
swift build -c release --product "$EXECUTABLE_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
