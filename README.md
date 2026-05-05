# Glance

Glance is a small macOS utility that adds a visual window picker to the standard `Command + \`` app-window cycling shortcut.

Press `Command + \`` to show the windows for the frontmost app, keep pressing it to cycle, then release Command to focus the selected window. While the picker is open, `Command + 1` through `Command + 0` jump directly to the first ten windows.

## Requirements

- macOS
- Swift toolchain / Xcode command line tools
- Accessibility permission for Glance

Glance uses macOS Accessibility APIs to inspect and focus windows. On first launch, macOS should prompt for permission. If it does not, enable Glance manually in System Settings > Privacy & Security > Accessibility.

## Download a Build

GitHub Actions builds `Glance.app` on every push and pull request.

1. Open the [Build Glance workflow](https://github.com/brooklynDev/Glance/actions/workflows/build-app.yml).
2. Select the latest successful run.
3. Download the `Glance-macOS` artifact.
4. Unzip it, then move `Glance.app` to `~/Applications` or `/Applications`.

These workflow builds are ad hoc signed, not notarized. macOS may require opening the app from Finder with Control-click > Open, or approving it in System Settings > Privacy & Security.

## Build

```sh
make build
```

This creates a local `build/Glance` executable.

## Build the App

```sh
make app
```

This creates and ad hoc signs `build/Glance.app`.

## Run

```sh
make run
```

## Install

```sh
make install
```

By default, this copies `Glance.app` to `~/Applications` and opens it. To install somewhere else:

```sh
make install INSTALL_DIR=/Applications
```

## Package

```sh
make zip
```

This creates `dist/Glance.zip`.

## Release Signing and Notarization

Local builds are ad hoc signed by default. For a Developer ID signed build, pass a signing identity:

```sh
make clean app SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

To notarize, first store credentials with `xcrun notarytool store-credentials`, then run:

```sh
make notarize \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="your-notarytool-profile"
```

The notarization target submits `dist/Glance.zip`, staples the ticket to `build/Glance.app`, and rebuilds the zip.

Gatekeeper assessment with `make assess` is expected to reject ad hoc local builds. Use it after building with a Developer ID identity and notarizing.

## Clean

```sh
make clean
```
