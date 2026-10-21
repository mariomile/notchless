#!/bin/zsh
# Builds Notchless.app (release, stripped, ad-hoc signed) and installs it into ~/Applications.
set -e
cd "$(dirname "$0")"
swift build -c release --arch arm64
APP=build/Notchless.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Notchless "$APP/Contents/MacOS/"
strip -x "$APP/Contents/MacOS/Notchless"
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp Icon/AppIcon.icns "$APP/Contents/Resources/"
# Ad-hoc signatures are identified by their hash, which changes on every build, so macOS would treat each
# build as a new app and drop its Accessibility permission. Pin the requirement to the bundle id instead.
codesign --force --sign - -r='designated => identifier "dev.mariomiletta.Notchless"' "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
if [[ "$1" == "--install" ]]; then
  pkill -x Notchless || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/Notchless.app
  cp -R "$APP" ~/Applications/
  # One copy on disk, so the permission prompt can only ever point at the installed app.
  rm -rf "$APP"
  open ~/Applications/Notchless.app
fi
