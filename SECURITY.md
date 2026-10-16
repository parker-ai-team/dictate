# Security and privacy notes

## What leaves your Mac

- Audio: never. Recording goes to a whisper.cpp server that the app starts on `127.0.0.1` and stops when the app quits.
- Text: only if the cleanup pass is on. Then the transcript (text, not audio) is sent to `api.anthropic.com` with your own API key. Turn cleanup off in Settings and the app makes no network connection at all.
- Nothing else. No analytics, no update check, no crash reporting.

You can spot-check this yourself: `scripts/verify.sh test/en_short.wav` runs the pipeline and samples the sockets the app and whisper-server had open while it ran (lsof every 50 ms, so a very short-lived connection could slip between samples; use a packet capture for a complete picture).

## The clipboard window

Text is inserted by writing it to the general pasteboard and sending Cmd+V, then restoring your previous clipboard 0.4 s later. During that window the text is on the clipboard like anything you copied. The item carries the `org.nspasteboard.TransientType` and `org.nspasteboard.ConcealedType` markers, so clipboard managers that follow the [nspasteboard.org](http://nspasteboard.org) convention skip it and keep no history copy. macOS does not enforce the markers: a tool that ignores them, or Universal Clipboard to your other Apple devices, may still see the text during those 0.4 s.

## Where the API key lives, and who can read it

In the macOS login keychain, as a generic password with the app's bundle id as service and `anthropic` as account, written and read through `/usr/bin/security`. Plainly: any process running as your user can read it without a prompt with

```
security find-generic-password -s com.parkeraiteam.dictate -a anthropic -w
```

and while you save a key in Settings it sits on the `security` command line for a few milliseconds, visible to same-user `ps`. Other users on the Mac cannot read it, and it is encrypted at rest. In practice this is about as safe as a file only you can read, not safer. The trade-off was made so that ad-hoc rebuilds (whose signature changes every time) do not trigger a keychain "allow access" prompt. The upgrade path, for a build with a stable signing identity, is Security.framework (`SecItemAdd` / `SecItemCopyMatching`) with an ACL limited to the app itself; that is future work. Remove the key with:

```
security delete-generic-password -s com.parkeraiteam.dictate -a anthropic
```

If you would rather not store a key at all, leave cleanup off; the app then never makes a network request.

## whisper-server on localhost

The app keeps whisper.cpp's server running on `127.0.0.1:8178` while it is open. That server (upstream design, whisper.cpp 1.8.4) answers with `Access-Control-Allow-Origin: *` and exposes `/inference` and `/load`, so a web page open in your browser could post its own audio to it or ask it to load another model. It cannot reach your microphone or your dictations. If a server already answers on the port, the app reuses it instead of starting its own; see Known limits in the README.

## Logs

`~/Library/Logs/Dictate.log` holds timings and character counts per dictation, never the text. `~/Library/Logs/Dictate-whisper.log` is whisper-server's own stderr (model load messages, language detection).

## Permissions the app asks for

- Microphone: to record while the hotkey is held.
- Accessibility: to see the hotkey (a CGEvent tap on modifier keys) and to post the Cmd+V keystroke that inserts the text.

The app has no sandbox and no entitlements; it is a plain signed bundle you build yourself. The headless `--insert` and `--hotkey-test` modes, which would let any local process paste through the app's Accessibility grant, are compiled in only by `scripts/build.sh --debug`, never in a normal build.

## Optional signing helper

`scripts/make-signing-cert.sh` creates a never-locking keychain, a private key any app may use without a prompt, and adds a self-signed certificate to your user trust settings as a code-signing root. The script header lists exactly that and the commands to remove it all.

## Reporting

Open a GitHub issue. For anything sensitive, use the repository's private vulnerability reporting if enabled, otherwise an issue with minimal detail and we will follow up.
