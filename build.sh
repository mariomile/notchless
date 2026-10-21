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
codesign --force --sign - "$APP"
if [[ "$1" == "--install" ]]; then
  pkill -x Notchless || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/Notchless.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Notchless.app
fi
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
