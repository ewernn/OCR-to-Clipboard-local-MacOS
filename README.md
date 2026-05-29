# Local OCR to Clipboard (macOS)

Press **Cmd+Shift+4**, drag over text, get the text in your clipboard. 100% native macOS, no cloud services, no global hotkey registration.

![Example](example.gif)

## Quick Setup

```bash
git clone https://github.com/ewernn/localOCRtoClipboard.git
cd localOCRtoClipboard
./setup.sh
```

## How it works (the trick)

Instead of writing a custom global hotkey listener (which would need accessibility permissions and a real app bundle), this hijacks macOS's built-in screenshot hotkey by redirecting where screenshots get saved:

```
Cmd+Shift+4  →  macOS writes PNG  →  /tmp/ocr-screenshots/  →  watcher OCRs it  →  clipboard
   (you)       (system default        (we redirect here via    (Swift binary +     (NSPasteboard)
                screenshot key)        `defaults write`)         Vision framework)
```

Three small pieces glue it together:

1. **Redirect screenshot save location** to `/tmp/ocr-screenshots/`:
   `defaults write com.apple.screencapture location /tmp/ocr-screenshots`
2. **Disable the 5-second preview thumbnail** so screenshots land in the watched folder immediately.
3. **Run a Swift binary as a LaunchAgent** that watches that folder via FSEvents. When a PNG appears, it runs `VNRecognizeTextRequest`, copies the result to the clipboard via `NSPasteboard`, then deletes the PNG.

No global hotkey listener, no accessibility prompts, no Python or Homebrew dependencies — just a small Swift binary running as a background service.

## Usage

Press **Cmd+Shift+4**, drag over the text. Done — it's on your clipboard.

## Uninstall

```bash
./setup.sh --uninstall
```

This also resets the screenshot save location and preview thumbnail to macOS defaults.

## Troubleshooting

Logs:
```bash
tail -f /tmp/ocr-watcher.log
tail -f /tmp/ocr-watcher-error.log
```

LaunchAgent status (should show the agent loaded with exit code 0):
```bash
launchctl list | grep ocr
```

If it's not running, re-run `./setup.sh`. The installed plist is at `~/Library/LaunchAgents/com.local.ocr-watcher.plist`.

## Requirements

- macOS 10.15+ (for the Vision text-recognition API)
- Xcode Command Line Tools: `xcode-select --install`

## Files

- `ocr-watcher.swift` — the daemon (~150 LOC)
- `compile.sh` — builds the Swift binary
- `setup.sh` — installs everything: compile, write LaunchAgent plist, configure screenshot settings, load agent
- `com.local.ocr-watcher.plist` — LaunchAgent template (binary path gets substituted at install time)
