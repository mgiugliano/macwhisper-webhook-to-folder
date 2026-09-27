#!/usr/bin/env bash
# Removes the macwhisper-webhook-to-folder LaunchAgent and installed files.
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/MacWhisperWebhookToFolder"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LABEL="local.macwhisper-webhook-to-folder"
PLIST="$LAUNCH_AGENTS/$LABEL.plist"
UID_NUM="$(id -u)"

launchctl bootout "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || true
rm -f "$PLIST"
rm -rf "$APP_SUPPORT"

echo "Uninstalled: $LABEL"
echo "Note: transcripts already written to your output folder are untouched."
