# macwhisper-webhook-to-folder

A tiny, dependency-free local server that receives [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper)'s
**Custom Webhook** callback and writes each finished transcript straight to a
Markdown file in a folder you choose — no Zapier, no Make.com, no cloud
service in between, and no vendor lock-in to a specific notes app.

If you use [Obsidian](https://obsidian.md), [ZenNotes](https://zennotes.org),
[Logseq](https://logseq.com), or literally any tool whose "vault" is just a
folder of files, this drops your call transcripts straight into it,
automatically, the moment a recording finishes.

## Why this exists

MacWhisper ships integrations for Zapier, Make.com, n8n, and a
purpose-built Obsidian REST API bridge — but nothing for the many notes apps
that are, under the hood, just a folder on disk. Routing a private meeting
transcript through a third-party SaaS webhook relay felt like the wrong
trade-off for something this simple. MacWhisper's "Custom Webhook" option
just needs *a* URL to POST JSON to — this project is 130 lines of Python
standard library that is that URL, running entirely on your own machine.

## Architecture

```
 ┌─────────────┐   finishes transcribing    ┌──────────────────────┐
 │  MacWhisper │ ──────────────────────────▶ │  POST 127.0.0.1:8765 │
 │  (your Mac) │   {"title","transcript"}    │        /hook         │
 └─────────────┘                             └───────────┬──────────┘
                                                           │
                                              macwhisper_bridge.py
                                              (stdlib http.server,
                                               launchd-managed)
                                                           │
                                     ┌─────────────────────┼─────────────────────┐
                                     ▼                     ▼                     ▼
                            write <title> — <ts>.md   macOS notification   optional: run
                            into MW_BRIDGE_OUTPUT_DIR    (osascript)       MW_BRIDGE_OPEN_COMMAND
                            (any folder: Obsidian vault,                  (e.g. `open -a Obsidian`)
                             ZenNotes vault, Logseq graph,
                             plain synced folder, ...)
```

Design choices, and why:

- **No dependencies.** `macwhisper_bridge.py` imports only the Python 3
  standard library (`http.server`, `json`, `pathlib`, `subprocess`). Nothing
  to `pip install`, nothing that can drift out of date or get flagged by a
  security scanner.
- **Loopback-only.** The server binds to `127.0.0.1`, never `0.0.0.0`. It is
  not reachable from your network, so — unlike MacWhisper's Make.com or
  Obsidian integrations — no API token or auth header is needed.
- **launchd, not a login item or a terminal window.** Installed as a
  per-user [LaunchAgent](https://www.launchd.info), so it starts silently at
  login, restarts itself if it ever crashes (`KeepAlive`), and needs no
  Terminal window kept open.
- **App-agnostic by construction.** The script only ever does two things:
  write a `.md` file, and (optionally) shell out to a command you configure.
  It has no idea what ZenNotes, Obsidian, or Logseq are — that's the point.
- **Collision-safe filenames.** MacWhisper often reuses a generic title
  (e.g. the calling app's name, `zoom.us`) across many unrelated calls. Every
  file is named `<title> — <YYYY-MM-DD HH.MM>.md`, and if two calls land in
  the same minute, `(2)`, `(3)`, ... are appended — nothing is ever
  overwritten.

## Requirements

- macOS (uses `launchd` and `osascript`; the Python script itself is
  portable, but `install.sh`/`uninstall.sh` are macOS-specific)
- Python 3.8+ (preinstalled on every modern Mac — check with `python3 --version`)
- [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper) with the
  "Custom Webhook" integration (Settings → Integrations)

## Install

```bash
git clone https://github.com/mgiugliano/macwhisper-webhook-to-folder.git
cd macwhisper-webhook-to-folder
./install.sh
```

By default this writes transcripts to `~/MacWhisperTranscripts` and listens
on port `8765`. To customize either before installing:

```bash
MW_BRIDGE_OUTPUT_DIR=~/Documents/ObsidianVault/Calls \
MW_BRIDGE_PORT=9000 \
./install.sh
```

`install.sh` will:
1. Copy `macwhisper_bridge.py` into `~/Library/Application Support/MacWhisperWebhookToFolder/`.
2. Create and load a LaunchAgent (`local.macwhisper-webhook-to-folder`) that
   runs it at login and keeps it alive.
3. Print the webhook URL and a `curl` command so you can verify it's working
   immediately, before touching MacWhisper at all.

Then, one manual step in MacWhisper itself (a native app preference — this
can't be scripted):

1. MacWhisper → **Settings → Integrations → Custom Webhook**
2. Paste the URL `install.sh` printed (default: `http://127.0.0.1:8765/hook`)
3. Enable **"Automatically send after finished transcription"**

That's it. Every finished transcript now lands in your chosen folder as a
plain `.md` file, with a macOS notification confirming it.

### Opening the note automatically (optional)

Set `MW_BRIDGE_OPEN_COMMAND` to any command that takes a file path as its
last argument, and it'll be run after every save:

```bash
# Open in Obsidian's default handler
MW_BRIDGE_OPEN_COMMAND="open" ./install.sh

# Open in a specific app
MW_BRIDGE_OPEN_COMMAND="open -a ZenNotes" ./install.sh
```

## Uninstall

```bash
./uninstall.sh
```

Stops and removes the LaunchAgent and the copied script. Transcripts already
written to your output folder are untouched.

## Configuration reference

All variables are read at process start; set them before running
`install.sh` (they get baked into the LaunchAgent's environment), or export
them and run `python3 macwhisper_bridge.py` directly for local testing.

| Variable               | Default                          | Meaning                                                                 |
|-------------------------|-----------------------------------|---------------------------------------------------------------------------|
| `MW_BRIDGE_PORT`        | `8765`                            | Port the receiver listens on (loopback only)                            |
| `MW_BRIDGE_OUTPUT_DIR`  | `~/MacWhisperTranscripts`         | Folder new transcripts are written into (created if missing)            |
| `MW_BRIDGE_OPEN_COMMAND`| *(unset)*                         | Command to run after each save, with the file path appended             |
| `MW_BRIDGE_NOTIFY`      | `1`                                | Set to `0` to skip the macOS notification                               |
| `MW_BRIDGE_LOG`         | `~/Library/Logs/macwhisper-webhook-to-folder.log` | Plain-text activity log (one line per request)   |

## Performance

This is a single-threaded-per-request stdlib `http.server` doing one file
write per call — there is essentially nothing to optimize, but here are
real measurements (`Python 3.14`, Apple Silicon Mac, LaunchAgent-managed
process) rather than guesses, from the `benchmark.sh` script included in
this repo:

| Metric                                              | Result           |
|------------------------------------------------------|--------------------|
| Idle memory footprint (RSS)                          | ~23 MB            |
| Memory after sustained use                            | unchanged (~23 MB) — no per-request growth |
| Cold start (process launch → first request served)   | ~94 ms            |
| Request latency, 45 KB transcript (~1 hour call)      | 1.3–2.4 ms, median 1.7 ms |
| Request latency, 180 KB transcript (~3–4 hour call)   | 1.3–2.9 ms, median 1.6 ms |
| Concurrent connections                                | handled (`ThreadingHTTPServer`), though MacWhisper only ever sends one at a time |

In practice: you will never notice this process running. It idles at zero
CPU, and even a multi-hour call's transcript is written in low-single-digit
milliseconds — the bottleneck in this whole pipeline is Whisper's own
transcription step, never this bridge.

Reproduce these numbers yourself:

```bash
./benchmark.sh
```

## Security notes

- The server binds to `127.0.0.1` only — it is unreachable from your local
  network or the internet. No authentication is implemented or needed for
  that reason.
- If you change the bind address or port-forward this to a broader network,
  add authentication first; the code has none.
- Transcripts are written with the same file permissions as your user
  account, into a folder you explicitly configure — this tool does not read,
  scan, or transmit your notes anywhere.

## Troubleshooting

- **Nothing shows up after a call.** Check `~/Library/Logs/macwhisper-webhook-to-folder.log`
  for a line for that call. If there's no line at all, verify the LaunchAgent
  is running: `launchctl list | grep macwhisper-webhook-to-folder`. If it's
  not listed, re-run `./install.sh`.
- **Port already in use.** Something else is bound to `8765`. Pick another
  port: `MW_BRIDGE_PORT=8899 ./install.sh`, then update the webhook URL in
  MacWhisper's settings to match.
- **MacWhisper shows a webhook error.** Confirm the LaunchAgent is running
  and test it directly:
  ```bash
  curl -i -X POST http://127.0.0.1:8765/hook \
    -H 'Content-Type: application/json' \
    -d '{"title":"Test","transcript":"hello"}'
  ```
  A `{"ok": true, ...}` response confirms the bridge itself works, so any
  remaining issue is on MacWhisper's side (webhook URL typo, integration not
  enabled, etc.).

## Contributing

Issues and PRs welcome. This project intentionally stays small and
dependency-free — if you want to extend it (e.g. Windows/Linux support via a
different service manager, YAML frontmatter, per-app routing), please open
an issue to discuss the approach first, as the goal is to keep the core
under 200 lines.

## License

[MIT](LICENSE)
