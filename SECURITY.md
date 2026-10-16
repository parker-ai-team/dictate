# Security and privacy notes

## What leaves your Mac

- Audio: never. Recording goes to a whisper.cpp server that the app starts on `127.0.0.1` and stops when the app quits.
- Text: only if the cleanup pass is on. Then the transcript (text, not audio) is sent to `api.anthropic.com` with your own API key. Turn cleanup off in Settings and the app makes no network connection at all.
- Nothing else. No analytics, no update check, no crash reporting.

You can check this yourself: `scripts/verify.sh test/en_short.wav` runs the pipeline and prints every socket the app and whisper-server opened while it ran.

## Where the API key lives

In the macOS login keychain, as a generic password with the app's bundle id as service and `anthropic` as account. It is read and written through `/usr/bin/security`. It is never written to a file, plist, log or the source tree. Remove it with:

```
security delete-generic-password -s com.parkeraiteam.dictate -a anthropic
```

## Logs

`~/Library/Logs/Dictate.log` holds timings and character counts per dictation, never the text. `~/Library/Logs/Dictate-whisper.log` is whisper-server's own stderr (model load messages, language detection).

## Permissions the app asks for

- Microphone: to record while the hotkey is held.
- Accessibility: to see the hotkey (a CGEvent tap on modifier keys) and to post the Cmd+V keystroke that inserts the text.

The app has no sandbox and no entitlements; it is a plain signed bundle you build yourself.

## Reporting

Open a GitHub issue. For anything sensitive, use the repository's private vulnerability reporting if enabled, otherwise an issue with minimal detail and we will follow up.
