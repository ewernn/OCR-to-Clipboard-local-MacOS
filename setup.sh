#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# OCR-to-Clipboard-local-MacOS — installer
#
# Two trigger modes (you pick one):
#   simple      No installs. Redirects the macOS screenshot-to-file location to a
#               watched folder, so Cmd+Shift+4 feeds OCR. Touches only `defaults`.
#   hammerspoon Leaves Cmd+Shift+3/4 100% normal. Binds ONE dedicated hotkey
#               (default Cmd+Shift+2) to an interactive region capture into the
#               watched folder. Installs Hammerspoon (open-source) for the hotkey.
#
# The OCR engine itself (ocr-watcher.swift) imports ONLY Apple system frameworks
# (Foundation, Vision, AppKit). No third-party libraries, no network access.
# ─────────────────────────────────────────────────────────────────────────────

SCREENSHOT_DIR="/tmp/ocr-screenshots"
STATE_DIR="$HOME/.config/ocr-to-clipboard"
STATE_FILE="$STATE_DIR/state"
HS_INIT="$HOME/.hammerspoon/init.lua"
HS_MARKER="OCR-to-Clipboard-local-MacOS"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="$SCRIPT_DIR/ocr-watcher"
PLIST_SOURCE="$SCRIPT_DIR/com.local.ocr-watcher.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.local.ocr-watcher.plist"

MODE=""
KEY=""
UNINSTALL=false

# ── Parse CLI arguments ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --uninstall) UNINSTALL=true; shift ;;
        --mode)      MODE="$2"; shift 2 ;;
        --key)       KEY="$2"; shift 2 ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--mode simple|hammerspoon] [--key <char>] [--uninstall]"
            exit 1
            ;;
    esac
done

# ── Uninstall ────────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
    echo "Uninstalling OCR-to-Clipboard-local-MacOS..."

    # Stop and remove the watcher LaunchAgent
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
    rm -f "$PLIST_DEST"
    rm -f "$BINARY_PATH"

    # Reverse whatever the chosen mode changed
    INSTALLED_MODE=""
    [ -f "$STATE_FILE" ] && INSTALLED_MODE="$(grep '^MODE=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)"

    if [ "$INSTALLED_MODE" = "simple" ]; then
        echo "Resetting screenshot settings to macOS defaults..."
        defaults delete com.apple.screencapture location 2>/dev/null || true
        defaults delete com.apple.screencapture show-thumbnail 2>/dev/null || true
        killall SystemUIServer 2>/dev/null || true
    fi

    if [ "$INSTALLED_MODE" = "hammerspoon" ] && [ -f "$HS_INIT" ]; then
        echo "Removing the hotkey block from $HS_INIT ..."
        # Delete everything between the marker comments (inclusive)
        sed -i '' "/-- >>> $HS_MARKER >>>/,/-- <<< $HS_MARKER <<</d" "$HS_INIT"
        echo "  (Hammerspoon itself was left installed. Remove it with: brew uninstall --cask hammerspoon)"
        echo "  Reload Hammerspoon's config (menubar → Reload Config) to drop the hotkey."
    fi

    rm -f "$STATE_FILE"
    echo "Uninstall complete."
    exit 0
fi

# ── Pick a mode (interactive if not passed) ──────────────────────────────────
if [ -z "$MODE" ]; then
    echo ""
    echo "How do you want to trigger OCR?"
    echo ""
    echo "  1) hammerspoon  (recommended) — dedicated hotkey, leaves Cmd+Shift+3/4"
    echo "                  untouched. Installs Hammerspoon (open-source) and needs"
    echo "                  ONE Accessibility permission you grant by hand."
    echo ""
    echo "  2) simple       — no installs, no permissions. BUT Cmd+Shift+4 stops"
    echo "                  saving normal screenshots (it gets OCR'd instead), and"
    echo "                  the preview thumbnail is disabled."
    echo ""
    read -r -p "Choose [1/2] (default 1): " choice
    case "$choice" in
        2) MODE="simple" ;;
        *) MODE="hammerspoon" ;;
    esac
fi

if [ "$MODE" != "simple" ] && [ "$MODE" != "hammerspoon" ]; then
    echo "Error: --mode must be 'simple' or 'hammerspoon'"
    exit 1
fi

# ── Common: compile + install the watcher LaunchAgent ────────────────────────
if ! command -v swiftc &> /dev/null; then
    echo "Error: Swift compiler not found."
    echo "Install Xcode Command Line Tools first:  xcode-select --install"
    exit 1
fi

echo ""
echo "Compiling OCR watcher (pure Apple frameworks, no dependencies)..."
"$SCRIPT_DIR/compile.sh"

mkdir -p "$SCREENSHOT_DIR"
mkdir -p "$STATE_DIR"

echo "Installing background watcher (LaunchAgent)..."
sed "s|BINARY_PATH_PLACEHOLDER|$BINARY_PATH|g" "$PLIST_SOURCE" > "$PLIST_DEST"
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

# ── Mode: simple ─────────────────────────────────────────────────────────────
if [ "$MODE" = "simple" ]; then
    echo "Configuring screenshot settings (simple mode)..."
    defaults write com.apple.screencapture location "$SCREENSHOT_DIR"
    defaults write com.apple.screencapture show-thumbnail -bool false
    killall SystemUIServer 2>/dev/null || true

    printf 'MODE=simple\n' > "$STATE_FILE"

    cat <<EOF

Setup complete!  (mode: simple — no packages installed)

Use it:
  Press Cmd+Shift+4, select text → it's OCR'd and copied to your clipboard.

Note: while installed, Cmd+Shift+4 no longer saves a normal screenshot to disk
(the image is OCR'd and deleted). Cmd+Shift+3 (full screen) also feeds OCR.

Screenshots are watched in: $SCREENSHOT_DIR (auto-cleaned on reboot)
Logs: /tmp/ocr-watcher.log  /tmp/ocr-watcher-error.log
EOF
    exit 0
fi

# ── Mode: hammerspoon ────────────────────────────────────────────────────────
# Pick the hotkey character (default 2 → Cmd+Shift+2)
if [ -z "$KEY" ]; then
    read -r -p "Hotkey will be Cmd+Shift+<key>. Which key? (default 2): " KEY
fi
KEY="${KEY:-2}"

# Ensure Hammerspoon is present (install via Homebrew cask if missing)
if [ ! -d "/Applications/Hammerspoon.app" ]; then
    if ! command -v brew &> /dev/null; then
        echo "Error: Hammerspoon is not installed and Homebrew is not available."
        echo "Install Homebrew (https://brew.sh) or Hammerspoon (https://hammerspoon.org), then re-run."
        exit 1
    fi
    cat <<'EOF'

This mode installs Hammerspoon (open-source: https://github.com/Hammerspoon/hammerspoon).

  SECURITY DISCLAIMER — please read:
  • Hammerspoon needs macOS "Accessibility" permission, which grants it
    system-wide ability to observe and synthesize keystrokes (the same
    permission a keylogger would need). This is required for ANY global
    hotkey tool, not something unique to this project.
  • It runs arbitrary Lua from ~/.hammerspoon/init.lua. Anything able to
    write that file inherits that system-wide power.
  • Hammerspoon is reputable, open-source, and notarized — but it is
    third-party software that you install and trust at your own risk.
  • Want zero installs and zero permissions instead? Cancel and run:
        ./setup.sh --mode simple

EOF
    read -r -p "Install Hammerspoon and continue? [y/N]: " confirm
    case "$confirm" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Cancelled. Nothing was installed."; exit 0 ;;
    esac

    echo "Installing Hammerspoon via Homebrew..."
    brew install --cask hammerspoon
fi

# Inject our hotkey block into ~/.hammerspoon/init.lua (without clobbering existing config)
mkdir -p "$(dirname "$HS_INIT")"
touch "$HS_INIT"
# Remove any previous block we added, then append a fresh one
sed -i '' "/-- >>> $HS_MARKER >>>/,/-- <<< $HS_MARKER <<</d" "$HS_INIT" 2>/dev/null || true

cat >> "$HS_INIT" <<EOF
-- >>> $HS_MARKER >>>
-- Cmd+Shift+$KEY → interactive region capture into the OCR watched folder.
-- The watcher OCRs the image and copies the text to the clipboard.
hs.hotkey.bind({"cmd", "shift"}, "$KEY", function()
  local dir = "$SCREENSHOT_DIR"
  hs.fs.mkdir(dir)
  local path = string.format("%s/ocr-%.0f.png", dir, hs.timer.secondsSinceEpoch() * 1000)
  hs.task.new("/usr/sbin/screencapture", nil, {"-i", path}):start()
end)
-- <<< $HS_MARKER <<<
EOF

printf 'MODE=hammerspoon\nKEY=%s\n' "$KEY" > "$STATE_FILE"

# Open the Accessibility pane so the user can grant permission
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true

cat <<EOF

Setup complete!  (mode: hammerspoon — hotkey Cmd+Shift+$KEY)

TWO manual steps you must do (they cannot be scripted):

  1. Open the Hammerspoon app (it was just installed). Click its menubar icon,
     it will load the config.

  2. Grant Hammerspoon "Accessibility" permission. A System Settings pane should
     have opened — enable Hammerspoon under:
       System Settings → Privacy & Security → Accessibility
     This is required for ANY app that binds a global hotkey. It lets Hammerspoon
     see your keypress; it does not give this tool network access.

Then use it:
  Press Cmd+Shift+$KEY, select text → it's OCR'd and copied to your clipboard.
  Cmd+Shift+3 and Cmd+Shift+4 keep working exactly as normal.

Screenshots are watched in: $SCREENSHOT_DIR (auto-cleaned on reboot)
Logs: /tmp/ocr-watcher.log  /tmp/ocr-watcher-error.log
EOF
