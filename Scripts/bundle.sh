#!/usr/bin/env bash
# Assembles Cobra.app from the SwiftPM executable.
#
# A real .app bundle is not cosmetic here: macOS attaches Microphone and
# Accessibility grants to a bundle identity, so a bare binary would re-prompt
# on every rebuild and could not carry usage-description strings at all.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP="$ROOT/build/Cobra.app"
BUNDLE_ID="ai.cobra.mac"
SIGN_IDENTITY="${COBRA_SIGN_IDENTITY:-Cobra Dev}"

cd "$ROOT"
# Regenerate the icon from the pixel map before packaging.
python3 "$ROOT/Scripts/make-icon.py"
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)/CobraMac"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cobra"
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT/.build/checkouts/FluidAudio/LICENSE" "$APP/Contents/Resources/FluidAudio-LICENSE.txt"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Cobra</string>
    <key>CFBundleDisplayName</key><string>Cobra</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Cobra</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Menu bar only: no Dock icon, no main window. -->
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Cobra listens while you hold the dictation key so it can turn your speech into text.</string>
</dict>
</plist>
PLIST

# Ad-hoc signatures change hash on every build, which makes TCC forget its
# grants. A self-signed identity (Scripts/make-cert.sh) keeps them stable.
# `find-identity -p codesigning` only lists *trusted* certificates, and the
# Cobra Dev cert is deliberately untrusted, so look the certificate up directly.
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
    echo "Signed with '$SIGN_IDENTITY' — permissions persist across rebuilds."
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
    echo "Ad-hoc signed. Run Scripts/make-cert.sh to stop re-granting permissions on every build."
fi

echo "Built $APP"
