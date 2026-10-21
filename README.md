# Notchless

A tiny macOS menu bar app for MacBooks with a notch. Click its button, right of the notch, and the notch opens like a Dynamic Island showing every menu bar item, including the ones hidden behind the notch. Click an item to open its menu.

- ~200 KB binary, no dependencies, zero CPU when idle (the menu bar is read only when you open it)
- Reads menu bar items through the Accessibility API, so it needs Accessibility permission
- macOS 14+, Apple Silicon

## Build

```bash
./build.sh --install
```

Builds a release, ad-hoc signs it and installs it into `~/Applications`. Ad-hoc signing means macOS asks for Accessibility permission again after every rebuild.

The app icon is drawn by `Icon/make-icon.swift`; run `swift Icon/make-icon.swift` to regenerate `Icon/AppIcon.icns`.

Right-click the button for Settings, Refresh and Quit. The button also works as the divider: items to its left are tucked away behind the notch, items to its right stay in the menu bar. Switch them in Settings or by right-clicking a tile, or Cmd-drag them across the button yourself.
