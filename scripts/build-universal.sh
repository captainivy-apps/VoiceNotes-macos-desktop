#!/usr/bin/env bash
#
# Builds a universal (arm64 + x86_64) Release .app bundle.
#
# Usage:
#   scripts/build-universal.sh
#
# The output is copied to: dist/VoiceNotes.app
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export PATH="/usr/local/bin:$PATH"

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="$REPO_ROOT/build"
DIST_DIR="$REPO_ROOT/dist"
APP_NAME="VoiceNotes"

echo "==> Building $APP_NAME ($CONFIGURATION, arm64 + x86_64)"
xcodebuild \
    -project VoiceNotes.xcodeproj \
    -scheme VoiceNotes \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "Error: build product not found at $BUILT_APP" >&2
    exit 1
fi

echo "==> Copying to $DIST_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
cp -R "$BUILT_APP" "$DIST_DIR/"

echo "==> Verifying architectures"
lipo -info "$DIST_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

echo ""
echo "Done: $DIST_DIR/$APP_NAME.app"
