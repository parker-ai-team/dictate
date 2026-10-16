#!/bin/zsh
# Generates short English and German test clips with the macOS speech
# synthesiser and converts them to 16 kHz mono WAV with afconvert (ships with
# macOS). Used by scripts/verify.sh. Nothing is downloaded.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p test
clip() {  # name voice "text"
  say -v "$2" -o "test/$1.aiff" "$3"
  afconvert -f WAVE -d LEI16@16000 -c 1 "test/$1.aiff" "test/$1.wav"
  rm -f "test/$1.aiff"
  echo "test/$1.wav"
}
clip en_short Daniel "Hello, this is a quick test of the dictation app."
clip en_long  Daniel "Okay so, um, I wanted to talk about the plan for next week. First we need to finish the report, then, you know, send the summary to the team. After that I think we should, we should look at the budget because it has not been updated yet. And finally, book the meeting for Thursday morning if everyone is free."
clip de_short Anna   "Guten Morgen, das ist ein kurzer Test der Diktierfunktion auf Deutsch."
