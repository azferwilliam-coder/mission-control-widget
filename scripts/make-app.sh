#!/bin/bash
# Builds "Mission Control Widget.app" from the source code.
#   scripts/make-app.sh                  → build/Mission Control Widget.app
#   scripts/make-app.sh --install        → also puts it in Applications and opens it
#   scripts/make-app.sh --snapshots DIR  → saves review pictures (sample data only) into DIR
# Needs Xcode (or Apple's Command Line Tools). Nothing is downloaded.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Mission Control Widget"
EXE="MissionControlWidget"
VERSION="$(cat VERSION 2>/dev/null || echo 0.1.0)"

echo "Building…"
swift build -c release --product "$EXE"
BIN="$(swift build -c release --product "$EXE" --show-bin-path)/$EXE"

APP="build/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE"

if [[ -f Resources/AppIcon.png ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>com.azferwilliam.missioncontrolwidget</string>
  <key>CFBundleExecutable</key><string>${EXE}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleDevelopmentRegion</key><string>en-GB</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Mission Control Widget shows your next event in its drawer. It only reads your calendar and never changes it.</string>
  <key>NSCalendarsUsageDescription</key><string>Mission Control Widget shows your next event in its drawer. It only reads your calendar and never changes it.</string>
</dict>
</plist>
PLIST

# Sign it just for this Mac (no Apple account needed).
codesign --force --sign - "$APP"
echo "Built: $APP"

case "${1:-}" in
  --snapshots)
    DIR="${2:-build/snapshots}"
    "$APP/Contents/MacOS/$EXE" --snapshot "$DIR"
    ;;
  --install)
    # Copy the new version next to the old one first, so a failed copy never leaves you without the app.
    NEW="/Applications/${APP_NAME}.app.new"
    OLD="/Applications/${APP_NAME}.app.old"
    rm -rf "$NEW" "$OLD"
    cp -R "$APP" "$NEW"
    # Quit any running copy (matched by its full path, as the name has spaces) and wait for it to go.
    pkill -f "/Contents/MacOS/${EXE}" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "/Contents/MacOS/${EXE}" >/dev/null 2>&1 || break
        sleep 0.5
    done
    pkill -9 -f "/Contents/MacOS/${EXE}" 2>/dev/null || true
    if [[ -d "/Applications/${APP_NAME}.app" ]]; then mv "/Applications/${APP_NAME}.app" "$OLD"; fi
    if ! mv "$NEW" "/Applications/${APP_NAME}.app"; then
      [[ -d "$OLD" ]] && mv "$OLD" "/Applications/${APP_NAME}.app"
      echo "Couldn't install the new app, so the old one was kept." >&2
      open "/Applications/${APP_NAME}.app" || true
      exit 1
    fi
    rm -rf "$OLD" "$APP"
    # Nudge Finder and the Dock to pick up a new icon.
    touch "/Applications/${APP_NAME}.app"
    open "/Applications/${APP_NAME}.app"
    echo "Installed in Applications and opened. Look at the top-left of your screen."
    ;;
esac
