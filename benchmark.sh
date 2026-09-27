#!/usr/bin/env bash
# Reproduces the numbers quoted in the README's Performance section.
# Runs a throwaway instance of the bridge on a separate port/folder so it
# never touches your real install.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8768
WORKDIR="$(mktemp -d)"
export MW_BRIDGE_PORT="$PORT"
export MW_BRIDGE_OUTPUT_DIR="$WORKDIR/output"
export MW_BRIDGE_NOTIFY=0
export MW_BRIDGE_LOG="$WORKDIR/bridge.log"

cleanup() {
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

python3 "$SRC_DIR/macwhisper_bridge.py" &
SERVER_PID=$!
sleep 1

echo "=== idle memory footprint (RSS) ==="
ps -o rss= -p "$SERVER_PID" | awk '{printf "RSS: %.1f MB\n", $1/1024}'

echo
echo "=== generating a ~45KB transcript (~1 hour call) ==="
python3 -c "
import random, json
words = ('so basically what I think we should do here is align on the roadmap and then '
         'circle back next week to review the numbers because honestly the client seemed '
         'pretty happy with the direction we presented yesterday afternoon').split()
text = ' '.join(random.choice(words) for _ in range(7000))
payload = json.dumps({'title': 'Bench call', 'transcript': text})
open('$WORKDIR/payload_small.json', 'w').write(payload)
print(len(payload), 'bytes')
"

echo
echo "=== latency: 20 sequential POSTs (small payload) ==="
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{time_total}\n" -X POST "http://127.0.0.1:$PORT/hook" \
    -H 'Content-Type: application/json' --data-binary @"$WORKDIR/payload_small.json"
done > "$WORKDIR/times_small.txt"
python3 -c "
times = sorted(float(l)*1000 for l in open('$WORKDIR/times_small.txt'))
n = len(times)
print(f'n={n}  min={times[0]:.2f}ms  median={times[n//2]:.2f}ms  max={times[-1]:.2f}ms')
"

echo
echo "=== generating a ~180KB transcript (~3-4 hour call) ==="
python3 -c "
import random, json
words = ('so basically what I think we should do here is align on the roadmap and then '
         'circle back next week to review the numbers because honestly the client seemed '
         'pretty happy with the direction we presented yesterday afternoon').split()
text = ' '.join(random.choice(words) for _ in range(28000))
payload = json.dumps({'title': 'Long bench call', 'transcript': text})
open('$WORKDIR/payload_big.json', 'w').write(payload)
print(len(payload), 'bytes')
"

echo
echo "=== latency: 10 sequential POSTs (large payload) ==="
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{time_total}\n" -X POST "http://127.0.0.1:$PORT/hook" \
    -H 'Content-Type: application/json' --data-binary @"$WORKDIR/payload_big.json"
done > "$WORKDIR/times_big.txt"
python3 -c "
times = sorted(float(l)*1000 for l in open('$WORKDIR/times_big.txt'))
n = len(times)
print(f'n={n}  min={times[0]:.2f}ms  median={times[n//2]:.2f}ms  max={times[-1]:.2f}ms')
"

echo
echo "=== memory after sustained use ==="
ps -o rss= -p "$SERVER_PID" | awk '{printf "RSS: %.1f MB\n", $1/1024}'
