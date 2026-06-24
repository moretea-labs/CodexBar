#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build_app.sh"

SOURCE="$ROOT/build/CodexBar.app"
TARGET="/Applications/CodexBar.app"

if ditto "$SOURCE" "$TARGET" 2>/dev/null; then
  echo "Installed: $TARGET"
else
  mkdir -p "$HOME/Applications"
  TARGET="$HOME/Applications/CodexBar.app"
  rm -rf "$TARGET"
  ditto "$SOURCE" "$TARGET"
  echo "Installed: $TARGET"
fi
open "$TARGET"
