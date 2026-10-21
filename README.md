# Notchless

A tiny macOS menu bar app for MacBooks with a notch. Click its button, right of the notch, and the notch opens like a Dynamic Island showing every menu bar item, including the ones hidden behind the notch. Click an item to open its menu.

- ~200 KB, no dependencies, zero CPU when idle (the menu bar is read only when you open it)
- Reads menu bar items through the Accessibility API, so it needs Accessibility permission
- macOS 14+, Apple Silicon

## Build

```bash
./build.sh --install
```

Builds a release, ad-hoc signs it and installs it into `~/Applications`. Ad-hoc signing means macOS asks for Accessibility permission again after every rebuild.

Right-click the button for Refresh and Quit. Cmd-drag moves it.
