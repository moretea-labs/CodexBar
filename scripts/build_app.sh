#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$ROOT/build/CodexBar.app"
ENTITLEMENTS="$ROOT/Resources/CodexBar.entitlements"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/CodexBar" "$APP_DIR/Contents/MacOS/CodexBar"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/CodexBar"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Signing app with: $SIGN_IDENTITY"
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"
else
  echo "Using ad-hoc signature for local development."
  codesign \
    --force \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign - \
    "$APP_DIR"
fi

codesign --verify --strict --verbose=2 "$APP_DIR"
echo "Built: $APP_DIR"
