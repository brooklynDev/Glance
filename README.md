# Glance

Glance is a small macOS utility that adds a visual window picker to the standard `Command + \`` app-window cycling shortcut.

Press `Command + \`` to show the windows for the frontmost app, keep pressing it to cycle, then release Command to focus the selected window. While the picker is open, `Command + 1` through `Command + 0` jump directly to the first ten windows.

Glance runs as a menu bar app. Use the menu bar icon to open Accessibility settings or quit the app.

## Requirements

- macOS
- Swift toolchain / Xcode command line tools
- Accessibility permission for Glance

Glance uses macOS Accessibility APIs to inspect and focus windows. When you first use the shortcut, macOS should prompt for permission. If it does not, enable Glance manually in System Settings > Privacy & Security > Accessibility.

## Download

Download the latest automated build from the [latest release](https://github.com/brooklynDev/Glance/releases/tag/latest), or use the direct download:

```text
https://github.com/brooklynDev/Glance/releases/download/latest/Glance.zip
```

Unzip it, then move `Glance.app` to `~/Applications` or `/Applications`.

Automated builds are ad hoc signed with a stable bundle requirement, not notarized. macOS may require opening the app from Finder with Control-click > Open, or approving it in System Settings > Privacy & Security.

Pull requests still upload temporary build artifacts to the [Build Glance workflow](https://github.com/brooklynDev/Glance/actions/workflows/build-app.yml), but the release page is the easiest place to get the current app.

## Accessibility Troubleshooting

If Glance keeps asking for Accessibility access even though it is already enabled, macOS is likely holding a stale permission entry from an older unsigned build.

Try either of these:

```sh
tccutil reset Accessibility com.brooklyndev.Glance
```

Then launch Glance again and approve it when prompted.

Or remove Glance from System Settings > Privacy & Security > Accessibility, add the copy in `/Applications` again, and turn it on.

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

Development builds use a stable designated requirement based on `com.brooklyndev.Glance`, so Accessibility approval should survive rebuilds. If you approved an older ad hoc build, remove and re-add Glance in System Settings > Privacy & Security > Accessibility once.

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

Local builds are ad hoc signed by default with a stable bundle requirement. For a Developer ID signed build, pass a signing identity:

```sh
make clean app SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

To let codesign generate the Developer ID requirement instead, clear the local requirement:

```sh
make clean app \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  SIGN_REQUIREMENTS=
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
