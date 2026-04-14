#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "Building Quickfiles in release mode..."
swift build -c release

APP_DIR="$ROOT_DIR/build/Quickfiles.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/Quickfiles"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/Quickfiles"
chmod +x "$MACOS_DIR/Quickfiles"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

echo
echo "App bundle created:"
echo "  $APP_DIR"
echo
echo "Run it with:"
echo "  open \"$APP_DIR\""
