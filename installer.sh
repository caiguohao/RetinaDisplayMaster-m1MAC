#!/bin/sh
set -eu

cd "$(dirname "$0")"
make dist

DEST="${DEST:-$HOME/Applications}"
mkdir -p "$DEST"
ditto "build/RetinaDisplayMaster.app" "$DEST/RetinaDisplayMaster.app"
xattr -cr "$DEST/RetinaDisplayMaster.app"
xattr -dr com.apple.FinderInfo "$DEST/RetinaDisplayMaster.app" 2>/dev/null || true
codesign --verify --deep --strict "$DEST/RetinaDisplayMaster.app"
echo "Installed $DEST/RetinaDisplayMaster.app"
