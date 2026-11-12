#!/bin/sh
# Baut build/Apfellicht.app samt Kontrollzentrum-Erweiterung, ohne Xcode-Projekt.
# Aufbau der Erweiterung nach dem Vorbild von LogoLight (github.com/Ark0N/LogoLight, MIT).
#
# Umgebung: VERSION, BUILD_NUMBER, BUNDLE_ID, SIGN_IDENTITY (Standard: erste „Apple Development“-Identität)
set -eu
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE_ID="${BUNDLE_ID:-de.timkanik.apfellicht}"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')"
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi

APP="build/Apfellicht.app"
APPEX="$APP/Contents/PlugIns/ApfellichtControls.appex"

fill() {
    sed -e "s/\$(BUNDLE_ID)/$BUNDLE_ID/g" -e "s/\$(VERSION)/$VERSION/g" -e "s/\$(BUILD_NUMBER)/$BUILD_NUMBER/g" "$1" > "$2"
    plutil -lint "$2" >/dev/null
}

echo "==> App bauen"
# SwiftPM trägt sonst das Deployment-Target als SDK ein; das Kontrollzentrum zeigt dann kein Icon.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
swift build -c release --product Apfellicht \
    -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION"
BIN="$(swift build -c release --product Apfellicht --show-bin-path)/Apfellicht"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Apfellicht"
fill Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/de.lproj "$APP/Contents/Resources/"

echo "==> Icons kompilieren"
# App-Icon und das eigene Symbol (Menüleiste, Kontrollzentrum) aus Resources/Assets.xcassets.
compile_assets() {
    xcrun actool --compile "$1" --platform macosx --minimum-deployment-target "$2" $3 \
        --output-partial-info-plist "build/assets-$2.plist" --output-format human-readable-text \
        --errors Resources/Assets.xcassets > "build/actool-$2.log" 2>&1 || { cat "build/actool-$2.log" >&2; exit 1; }
}
compile_assets "$APP/Contents/Resources" 14.0 "--app-icon AppIcon"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"

echo "==> Kontrollzentrum-Erweiterung bauen"
PROCESSOR="$(xcrun --find appintentsmetadataprocessor)"
OBJ="build/controls"
TARGET="arm64-apple-macos26.0"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TOOLCHAIN="$(cd "$(dirname "$PROCESSOR")/../.." && pwd)"
rm -rf "$OBJ"
mkdir -p "$OBJ" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
SOURCES="Controls/ApfellichtControls.swift Sources/ApfellichtCore/ControlLink.swift"
# shellcheck disable=SC2086
xcrun swiftc -module-name ApfellichtControls -O -whole-module-optimization -swift-version 6 \
    -sdk "$SDK" -target "$TARGET" -application-extension -parse-as-library \
    -emit-const-values-path "$OBJ/ApfellichtControls.swiftconstvalues" \
    -const-gather-protocols-list Controls/const_extract_protocols.json \
    -Xlinker -application_extension -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$APPEX/Contents/MacOS/ApfellichtControls" $SOURCES
fill Controls/Info.plist "$APPEX/Contents/Info.plist"
cp -R Controls/en.lproj Controls/de.lproj "$APPEX/Contents/Resources/"
compile_assets "$APPEX/Contents/Resources" 26.0 ""
printf '%s\n' $SOURCES > "$OBJ/sources.txt"
echo "$OBJ/ApfellichtControls.swiftconstvalues" > "$OBJ/constvalues.txt"
: > "$OBJ/none.txt"
"$PROCESSOR" --toolchain-dir "$TOOLCHAIN" --module-name ApfellichtControls --sdk-root "$SDK" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" \
    --platform-family macOS --deployment-target 26.0 --target-triple "$TARGET" \
    --bundle-identifier "$BUNDLE_ID.Controls" --output "$APPEX/Contents/Resources" \
    --binary-file "$APPEX/Contents/MacOS/ApfellichtControls" --source-file-list "$OBJ/sources.txt" \
    --swift-const-vals-list "$OBJ/constvalues.txt" --metadata-file-list "$OBJ/none.txt" \
    --static-metadata-file-list "$OBJ/none.txt" --compile-time-extraction --deployment-aware-processing \
    --no-app-shortcuts-localization > "$OBJ/metadata.log" 2>&1 \
    || { cat "$OBJ/metadata.log" >&2; exit 1; }
test -d "$APPEX/Contents/Resources/Metadata.appintents" || { echo "Fehler: keine App-Intents-Metadaten" >&2; exit 1; }
fill Controls/Controls.entitlements "$OBJ/Controls.entitlements"

echo "==> Signieren ($SIGN_IDENTITY)"
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
    --entitlements "$OBJ/Controls.entitlements" "$APPEX"
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none "$APP"
codesign --verify --strict --deep "$APP"
echo "==> Fertig: $APP"
