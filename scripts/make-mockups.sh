#!/bin/sh
# Rendert die README-Bilder aus design/mockups.html (braucht Google Chrome) und das Menü aus der App.
set -eu
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
APP="build/Apfellicht.app/Contents/MacOS/Apfellicht"
mkdir -p docs/images
for lang in en de; do
    for mode in light dark; do
        "$APP" --render-menu "$PWD/docs/images/menu-$lang-$mode.png" "$mode" -AppleLanguages "($lang)"
    done
    for view in hero compare; do
        "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
            --window-size=1600,900 --force-device-scale-factor=1.5 \
            --screenshot="$PWD/docs/images/$view-$lang.png" "file://$PWD/design/mockups.html?view=$view&lang=$lang" 2>/dev/null
    done
done
ls -la docs/images
