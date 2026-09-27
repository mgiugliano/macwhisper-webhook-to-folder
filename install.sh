#!/usr/bin/env bash
# Installs macwhisper-webhook-to-folder as a per-user LaunchAgent (macOS).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/MacWhisperWebhookToFolder"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LABEL="local.macwhisper-webhook-to-folder"
PLIST="$LAUNCH_AGENTS/$LABEL.plist"
UID_NUM="$(id -u)"

# Optional overrides, e.g.:
#   MW_BRIDGE_PORT=9000 MW_BRIDGE_OUTPUT_DIR=~/Obsidian/Calls ./install.sh
PORT="${MW_BRIDGE_PORT:-8765}"
OUTPUT_DIR="${MW_BRIDGE_OUTPUT_DIR:-$HOME/MacWhisperTranscripts}"
OPEN_COMMAND="${MW_BRIDGE_OPEN_COMMAND:-}"

mkdir -p "$APP_SUPPORT" "$LAUNCH_AGENTS" "$HOME/Library/Logs" "$OUTPUT_DIR"
cp "$SRC_DIR/macwhisper_bridge.py" "$APP_SUPPORT/macwhisper_bridge.py"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$APP_SUPPORT/macwhisper_bridge.py</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>MW_BRIDGE_PORT</key>
        <string>$PORT</string>
        <key>MW_BRIDGE_OUTPUT_DIR</key>
        <string>$OUTPUT_DIR</string>
        <key>MW_BRIDGE_OPEN_COMMAND</key>
        <string>$OPEN_COMMAND</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/macwhisper-webhook-to-folder.out.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/macwhisper-webhook-to-folder.err.log</string>
</dict>
</plist>
PLIST_EOF

launchctl bootout "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl enable "gui/$UID_NUM/$LABEL"

sleep 1
echo "Installed and started: $LABEL"
echo "Output folder: $OUTPUT_DIR"
echo
echo "Webhook URL to paste into MacWhisper -> Settings -> Integrations -> Custom Webhook:"
echo "  http://127.0.0.1:$PORT/hook"
echo
echo "Verify it's listening:"
echo "  curl -s -X POST http://127.0.0.1:$PORT/hook -H 'Content-Type: application/json' -d '{\"title\":\"Bridge test\",\"transcript\":\"hello from install.sh\"}'"
echo
echo "Logs: ~/Library/Logs/macwhisper-webhook-to-folder*.log"
