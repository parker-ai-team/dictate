# Changelog

All notable changes to Dictate are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-16

Initial public release.

### Added

- Push-to-talk dictation from the menu bar: hold a modifier key (Right Option by default; Left Option, Right Command, Right Control or Fn selectable), or tap-to-start / tap-to-stop mode.
- Local speech-to-text with whisper.cpp: the app starts `whisper-server` on `127.0.0.1` with the `ggml-large-v3-turbo` model (configurable), keeps it warm, and stops it on quit. Automatic language detection.
- Optional cleanup pass through the Anthropic Messages API (`claude-haiku-5-5` by default) using the user's own key: filler words, punctuation, capitalisation, simple lists. Falls back to the raw transcript on any error or timeout; output longer than the input is rejected.
- Insertion at the cursor by clipboard paste (Cmd+V) with the previous clipboard restored after 0.4 s; every insertion ends with terminal punctuation and one space.
- Settings window: hotkey, mode, sounds, cleanup on/off, model, timeout, API key (macOS Keychain), whisper paths and port, permissions status with deep links, launch at login.
- Floating status pill (listening / transcribing / formatting / inserted) and a menu-bar icon that changes with state.
- Permission handling: polls for the Accessibility grant without a relaunch, asks for the microphone on first use, links to the right System Settings panes.
- Headless `--selftest <wav> [--no-format]` mode and `scripts/verify.sh`, which samples the app's sockets during a run so the privacy statement can be spot-checked.
- Build with `swiftc` only (`scripts/build.sh`), ad-hoc signing by default, optional self-signed identity helper, icon generation from SVG with AppKit and `iconutil`.

### Security

- The `--insert` and `--hotkey-test` headless modes are compiled in only by `scripts/build.sh --debug`; release builds refuse them, so no other local process can paste through the app's Accessibility grant.
- Pasteboard items are marked `org.nspasteboard.TransientType` and `org.nspasteboard.ConcealedType` so clipboard managers that follow the convention skip them.
- SECURITY.md states what leaves the Mac, who can read the stored API key, the clipboard window, and what whisper-server exposes on localhost.
