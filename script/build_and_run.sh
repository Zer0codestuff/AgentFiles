#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_EXECUTABLE="AgentFiles"
APP_DISPLAY_NAME="Agent Files"
BUNDLE_ID="com.gabrielemonni.AgentFiles"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE"

cd "$ROOT_DIR"
pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true

swift build --product "$APP_EXECUTABLE"
BUILD_BINARY="$(swift build --show-bin-path)/$APP_EXECUTABLE"

if [[ "$APP_BUNDLE" != "$ROOT_DIR/dist/Agent Files.app" ]]; then
    echo "Refusing to replace an unexpected bundle path." >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/Support/Info.plist" "$APP_CONTENTS/Info.plist"

# Compile the Icon Composer file so macOS 26 applies its own icon shape and glass.
ICON_WORK="$(mktemp -d)"
xcrun actool "$ROOT_DIR/Icon/AppIcon.icon" --compile "$ICON_WORK" --platform macosx \
    --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist "$ICON_WORK/partial.plist" >/dev/null
cp "$ICON_WORK/Assets.car" "$ICON_WORK/AppIcon.icns" "$APP_CONTENTS/Resources/"
rm -rf "$ICON_WORK"
chmod +x "$APP_BINARY"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        for _ in {1..20}; do
            if pgrep -x "$APP_EXECUTABLE" >/dev/null; then
                exit 0
            fi
            sleep 0.1
        done
        echo "$APP_DISPLAY_NAME did not stay running." >&2
        exit 1
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
