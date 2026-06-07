# OCR-to-Clipboard-local-MacOS

Press a hotkey, drag over text, get the text in your clipboard. **100% on-device** — the OCR runs through Apple's Vision framework, nothing is uploaded, nothing phones home.

![Example](example.gif)

## No third-party packages

The OCR engine (`ocr-watcher.swift`) imports **only Apple system frameworks**:

```swift
import Foundation
import Vision
import AppKit
```

No pip, no npm, no Swift packages, no network calls. It's a ~150-line Swift binary that watches a folder, runs `VNRecognizeTextRequest` on images that appear, and copies the result to the clipboard.

(The optional **Hammerspoon** trigger mode installs one well-known open-source app to provide the hotkey — see below. The **simple** mode installs nothing at all.)

## Quick Setup

```bash
git clone https://github.com/ewernn/OCR-to-Clipboard-local-MacOS.git
cd OCR-to-Clipboard-local-MacOS
./setup.sh
```

`setup.sh` asks which trigger mode you want.

## Two trigger modes

Both modes use the same watcher; they differ only in **how a screenshot gets into the watched folder**.

### 1. Hammerspoon (recommended) — dedicated hotkey

Binds **one** hotkey (default **Cmd+Shift+2**, configurable) to an interactive region capture that goes straight into the OCR folder.

- ✅ Leaves Cmd+Shift+3 and Cmd+Shift+4 **completely normal** — regular screenshots still work.
- ✅ Instant trigger (Hammerspoon fires on keydown).
- ⚠️ Installs [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) (open-source) via Homebrew.
- ⚠️ Requires **one** permission you grant by hand: **Accessibility**. This is mandatory for *any* app that binds a global hotkey — it lets Hammerspoon see the keypress. It does **not** grant network access.

```bash
./setup.sh --mode hammerspoon --key 2
```

### 2. Simple — no installs, no permissions

Redirects the macOS screenshot-to-file location to the watched folder, so Cmd+Shift+4 feeds OCR. Touches only `defaults` settings.

- ✅ Installs nothing, grants no permissions.
- ⚠️ **Cmd+Shift+4 stops saving normal screenshots** — the image is OCR'd and deleted. Cmd+Shift+3 (full screen) also feeds OCR.
- ⚠️ Disables the 5-second preview thumbnail (so files land immediately).

```bash
./setup.sh --mode simple
```

## How it works (the watcher)

```
hotkey → screenshot PNG → /tmp/ocr-screenshots/ → watcher OCRs it → clipboard
         (Hammerspoon or    (the watched folder)    (Swift + Vision)   (NSPasteboard)
          macOS native)
```

The Swift binary runs as a **LaunchAgent**, watching the folder via FSEvents. When an image appears it waits for the file to finish writing, runs Vision text recognition, copies the text to the clipboard via `NSPasteboard`, shows a notification, and deletes the image.

## Permissions summary

| Mode | Installs | Permissions you must grant |
|------|----------|----------------------------|
| simple | nothing | none |
| hammerspoon | Hammerspoon (Homebrew) | Accessibility (for the hotkey) |

The watcher itself needs no special permission — it only reads image files from `/tmp` and writes to the clipboard.

## Uninstall

```bash
./setup.sh --uninstall
```

Reverses whatever the chosen mode changed (screenshot settings for *simple*, the hotkey block for *hammerspoon*) and removes the watcher. Hammerspoon, if installed, is left in place — remove it yourself with `brew uninstall --cask hammerspoon`.

## Troubleshooting

```bash
tail -f /tmp/ocr-watcher.log          # watcher activity
tail -f /tmp/ocr-watcher-error.log    # errors
launchctl list | grep ocr             # is the agent loaded?
```

If it's not running, re-run `./setup.sh`. The installed plist lives at `~/Library/LaunchAgents/com.local.ocr-watcher.plist`.

For **hammerspoon** mode, if the hotkey does nothing: open the Hammerspoon app, check the menubar console for errors, and confirm Hammerspoon is enabled under System Settings → Privacy & Security → Accessibility.

## Requirements

- macOS 10.15+ (for the Vision text-recognition API)
- Xcode Command Line Tools: `xcode-select --install`
- Hammerspoon mode only: Homebrew (https://brew.sh)

## Files

- `ocr-watcher.swift` — the daemon (~150 LOC, Apple frameworks only)
- `compile.sh` — builds the Swift binary
- `setup.sh` — interactive installer (two modes) + `--uninstall`
- `com.local.ocr-watcher.plist` — LaunchAgent template (binary path substituted at install time)
