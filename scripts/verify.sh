#!/bin/zsh
# Runs the transcription + cleanup pipeline on a WAV file through the built
# app and samples the network sockets of the app and of whisper-server while
# it runs. Prints the timings and every remote endpoint seen. This is how the
# privacy statement in the README is checked.
#
#   scripts/make-test-clips.sh                       once, generates test/*.wav
#   scripts/verify.sh test/en_short.wav              cleanup on
#   scripts/verify.sh test/en_short.wav --no-format  cleanup off
#
# Uses build/Dictate.app if present, else ~/Applications/Dictate.app.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="${DICTATE_BIN:-build/Dictate.app/Contents/MacOS/Dictate}"
[[ -x "$BIN" ]] || BIN="$HOME/Applications/Dictate.app/Contents/MacOS/Dictate"
WAV="${1:?wav file}"
shift
OUT=$(mktemp)
NET=$(mktemp)

"$BIN" --selftest "$WAV" "$@" > "$OUT" 2>/dev/null &
PID=$!
while kill -0 $PID 2>/dev/null; do
  PIDS="$PID $(pgrep -x whisper-server | tr '\n' ' ')"
  lsof -nP -a -i -p "${PIDS// /,}" 2>/dev/null | awk 'NR>1 {print $1, $9, $10}' >> "$NET"
  sleep 0.05
done
wait $PID
cat "$OUT"
echo "[net] unique sockets seen during the run (process, endpoint, state):"
sort -u "$NET" | sed 's/^/[net]   /'
echo "[net] remote (non-localhost) endpoints:"
grep -v '127.0.0.1' "$NET" | grep -v '\[::1\]' | awk '{print $1, $2}' | sort -u | sed 's/^/[net]   /' || true
rm -f "$OUT" "$NET"
