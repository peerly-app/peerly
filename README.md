# Peero

Local network messaging. Two devices that open the app on the same network discover each other automatically and can exchange text, voice messages and files, one to one. No server, no account, no cloud — nothing leaves the network you are already on.

## Install

**Linux & macOS** — one command, auto-detects the platform (`.deb` on Debian/Ubuntu, an AppImage on other distributions, Homebrew on macOS):
```
curl -fsSL https://peero-app.github.io/peero/install.sh | bash
```

**Windows** (PowerShell):
```
powershell -c "irm https://peero-app.github.io/peero/install.ps1 | iex"
```

**macOS, directly via Homebrew** (recommended — what the script above runs under the hood):
```
brew install --cask peero-app/tap/peero
```

Prefer a manual download? `.deb`, `.AppImage` and `peero-setup.exe` are all on the [releases page](https://github.com/peero-app/peero/releases/latest). Once installed, Settings → Check for Updates keeps the app current (installed automatically and restarted on Linux AppImage, Windows and macOS; the `.deb` build just opens the release page, since updating it needs `sudo`).

## Uninstall

| Install method | Command |
|---|---|
| Debian/Ubuntu (`.deb`) | `sudo apt remove peero` |
| Linux AppImage | `rm ~/.local/bin/peero.AppImage` |
| macOS (Homebrew) | `brew uninstall --cask peero && brew untap peero-app/tap` |
| Windows | Settings → Apps, or run `unins000.exe` from the install folder |

## How it works

- **Discovery** — every device announces itself roughly every 3s on the UDP multicast group `239.100.100.100:53320` (id, alias, platform, message server port). Devices not seen for 10s drop off the list.
- **Messages** — every device runs a small local HTTP server; sending a message is a plain `POST /message` to the recipient's IP and port. Voice clips and files are announced the same way, then fetched from that server on demand — a file only transfers once the recipient accepts it.
- **Consent** — a conversation has to be accepted by both sides before any message goes through, and a peer can be blocked at any point.
- **History** — persisted to disk with Hive (one box per conversation, plus an index box for the list). Profile photos, voice messages and file metadata are stored the same way; the transferred files themselves live unencrypted in the app's support directory.

## Languages

The app ships in English, French, Spanish, German, Italian and Portuguese. It follows the system language on first launch and falls back to English, and the choice can be changed in Settings.

## Known limitation

No encryption and no authentication: messages travel in the clear, and a device on the network could spoof an `id`. Acceptable for a trusted LAN; to be addressed later if needed, for instance with a pinned self-signed certificate.

## Building per platform

### Linux / Windows (desktop)
```
flutter run -d linux    # or -d windows
```
No particular permission to configure.

### Android
```
flutter run -d <device>
```
Requires the Android SDK. The only permission needed is `INTERNET`, already declared in `android/app/src/main/AndroidManifest.xml`.

### macOS
```
flutter run -d macos
```
Requires a Mac with Xcode. The network entitlements (`network.client` / `network.server`) are already configured in `macos/Runner/*.entitlements`.

### iOS — a manual step is required before testing on a physical iPhone

Network discovery (UDP multicast) requires Apple's **`com.apple.developer.networking.multicast`** entitlement on iOS. It is already present in `ios/Runner/Runner.entitlements` and referenced in the Xcode project, but the entitlement has to be **approved manually by Apple**:

1. Have an Apple Developer Program account.
2. Request it at https://developer.apple.com/contact/request/networking-multicast (observed delay: 3 to 14 days, with no online tracking).
3. Once approved, attach the entitlement to the App ID in the developer portal.

Without it, the app will not discover other devices on a **physical iPhone** (the iOS Simulator has no such restriction). The code is ready; only this administrative step on Apple's side is missing.

## Tests

```
flutter analyze
flutter test
flutter test --coverage    # writes coverage/lcov.info
```

The suite covers ~92% of the hand-written lines in `lib/` (excluding the generated `lib/l10n/`). What is left uncovered depends on native plugins that are unavailable under `flutter test`: `record`, `audioplayers`, `media_kit`, `flutter_local_notifications`, `image_picker` / `file_picker`, reading the Wi-Fi SSID, and `main()` itself.

Widget tests use in-memory repositories (`test/helpers/in_memory_repositories.dart`): `testWidgets` swaps in a fake clock, which Hive's write queue cannot drain.

`test/l10n/translations_test.dart` checks that every language translates all 67 template keys. `flutter gen-l10n` silently fills any gap with English rather than failing, so nothing else would flag a language falling behind.
