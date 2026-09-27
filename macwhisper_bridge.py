#!/usr/bin/env python3
"""Local webhook receiver: MacWhisper -> a Markdown file in your notes folder.

MacWhisper (https://goodsnooze.gumroad.com/l/macwhisper) has a "Custom
Webhook" integration that POSTs {"title": ..., "transcript": ...} as JSON to
a URL of your choice once a recording finishes transcribing. This script is
that URL's server: it listens on localhost only, and on every request writes
the transcript out as a plain Markdown file in a folder you choose.

That folder can be an Obsidian vault, a ZenNotes vault, a Logseq graph, a
plain iCloud/Dropbox-synced folder, or anything else that's "just files" --
this script doesn't care, it only writes Markdown.

Zero third-party dependencies (Python 3 standard library only).
"""

import json
import os
import re
import subprocess
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("MW_BRIDGE_PORT", "8765"))
OUTPUT_DIR = Path(
    os.environ.get("MW_BRIDGE_OUTPUT_DIR", str(Path.home() / "MacWhisperTranscripts"))
).expanduser()
NOTIFY = os.environ.get("MW_BRIDGE_NOTIFY", "1") != "0"
LOG_PATH = Path(
    os.environ.get(
        "MW_BRIDGE_LOG",
        str(Path.home() / "Library" / "Logs" / "macwhisper-webhook-to-folder.log"),
    )
).expanduser()

# Optional: if set, this command is run (with the new file's absolute path as
# its final argument) after each transcript is saved -- e.g. to open it in
# your notes app of choice. Left unset by default. Example:
#   export MW_BRIDGE_OPEN_COMMAND="open -a Obsidian"
OPEN_COMMAND = os.environ.get("MW_BRIDGE_OPEN_COMMAND", "").strip()

ILLEGAL_CHARS = re.compile(r'[\/:*?"<>|]')


def log(message: str) -> None:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with LOG_PATH.open("a") as f:
        f.write(f"[{stamp}] {message}\n")


def sanitize_title(title: str) -> str:
    title = title.strip() or "Untitled transcript"
    title = ILLEGAL_CHARS.sub("-", title)
    return title[:150]


def unique_path(directory: Path, base_name: str) -> Path:
    """Avoid clobbering an existing file with the same title + minute."""
    candidate = directory / f"{base_name}.md"
    if not candidate.exists():
        return candidate
    n = 2
    while True:
        candidate = directory / f"{base_name} ({n}).md"
        if not candidate.exists():
            return candidate
        n += 1


def notify(title: str) -> None:
    if not NOTIFY:
        return
    safe_title = title.replace('"', "'")
    script = (
        f'display notification "Transcript saved" '
        f'with title "MacWhisper" subtitle "{safe_title}"'
    )
    subprocess.run(["osascript", "-e", script], check=False)


def run_open_command(path: Path) -> None:
    if not OPEN_COMMAND:
        return
    subprocess.run(OPEN_COMMAND.split() + [str(path)], check=False)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        try:
            data = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            log(f"Bad JSON payload ({len(raw)} bytes)")
            self._send(400, {"ok": False, "error": "invalid json"})
            return

        title = sanitize_title(str(data.get("title", "")))
        transcript = str(data.get("transcript", ""))
        if not transcript.strip():
            log("Empty transcript received, ignoring")
            self._send(400, {"ok": False, "error": "empty transcript"})
            return

        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y-%m-%d %H.%M")
        path = unique_path(OUTPUT_DIR, f"{title} — {stamp}")
        path.write_text(transcript, encoding="utf-8")
        log(f"Saved: {path} ({len(transcript)} chars)")

        notify(title)
        run_open_command(path)

        self._send(200, {"ok": True, "path": str(path)})

    def log_message(self, format, *args):  # noqa: A002 - stdlib signature
        pass  # quiet stdout; see LOG_PATH for a persistent record


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    log(f"Listening on http://127.0.0.1:{PORT} -> {OUTPUT_DIR}")
    server.serve_forever()


if __name__ == "__main__":
    main()
