#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="CodexBar"
APP_PATH="$ROOT/build/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
PKG_PATH="${PKG_PATH:-$ROOT/build/$APP_NAME-$VERSION.pkg}"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$ROOT/scripts/build_app.sh"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

rm -f "$PKG_PATH"

PKG_ARGS=(
  --component "$APP_PATH"
  --install-location /Applications
  --identifier com.greyson.codexbar.pkg
  --version "$VERSION"
)

if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
  PKG_ARGS+=(--sign "$INSTALLER_IDENTITY")
fi

pkgbuild "${PKG_ARGS[@]}" "$PKG_PATH"

if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
  pkgutil --check-signature "$PKG_PATH"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${SIGN_IDENTITY:-}" || -z "${INSTALLER_IDENTITY:-}" ]]; then
    echo "PKG notarization requires SIGN_IDENTITY and INSTALLER_IDENTITY." >&2
    exit 1
  fi

  xcrun notarytool submit "$PKG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$PKG_PATH"
  xcrun stapler validate "$PKG_PATH"
fi

echo "Created: $PKG_PATH"
