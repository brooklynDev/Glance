# Glance

Glance is a small macOS utility that adds a visual window picker to the standard `Command + \`` app-window cycling shortcut.

Press `Command + \`` to show the windows for the frontmost app, keep pressing it to cycle, then release Command to focus the selected window. While the picker is open, `Command + 1` through `Command + 0` jump directly to the first ten windows.

## Requirements

- macOS
- Swift toolchain / Xcode command line tools
- Accessibility permission for Glance

Glance uses macOS Accessibility APIs to inspect and focus windows. On first launch, macOS should prompt for permission. If it does not, enable Glance manually in System Settings > Privacy & Security > Accessibility.

## Build

```sh
make build
```

This creates a local `Glance` executable.

## Run

```sh
make run
```

## Clean

```sh
make clean
```

## Status

This is currently a compact AppKit prototype built as a command-line executable. The next step is turning it into a proper `.app` bundle with an icon, signing/notarization path, and a more polished install flow.
