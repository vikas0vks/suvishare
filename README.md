<div align="center">
  <img src="app/assets/icon/suvi-share-256.png" width="112" alt="Suvi Share logo">
  <h1>Suvi Share</h1>
  <p><strong>Share across the room, not across the internet.</strong></p>
  <p>Fast, private file sharing for Android, Windows, Linux, and any modern browser.</p>

  [![Latest release](https://img.shields.io/github/v/release/vikas0vks/suvishare?display_name=tag&style=for-the-badge&color=6750A4)](https://github.com/vikas0vks/suvishare/releases/latest)
  [![Build](https://img.shields.io/github/actions/workflow/status/vikas0vks/suvishare/ci.yml?branch=main&style=for-the-badge&label=build)](https://github.com/vikas0vks/suvishare/actions/workflows/ci.yml)
  [![License](https://img.shields.io/github/license/vikas0vks/suvishare?style=for-the-badge)](LICENSE)
</div>

---

Suvi Share moves files, folders, photos, videos, music, documents, archives, and text directly between devices on the same local network. There is no account, cloud storage, advertising, or analytics.

## Highlights

| | Feature | What it gives you |
|---|---|---|
| ⚡ | Direct LAN transfers | Stream device-to-device without uploading files to a server |
| 🗂️ | Category-first picker | General, Documents, Photos, Videos, Music, Compressed, and Other |
| 🔎 | Resilient discovery | Multicast, register-back, subnet scan, manual address, and QR |
| 🔐 | Explicit trust | Ask every time, trusted-device auto-save, PIN mode, and blocking |
| ♻️ | Resume support | Continue interrupted transfers and verify optional SHA-256 checksums |
| 🌐 | Web Share | Send and receive from a browser without installing the app |
| 🎨 | Six palettes | Suvi, Ocean, Sunset, Forest, Lavender, and Rose in light/dark/system mode |
| ⬆️ | Release updates | Automatic GitHub Releases check with a manual check and download action |
| 🌍 | Localized | English and हिन्दी, bundled for fully offline rendering |

## Install

Download the newest build from [GitHub Releases](https://github.com/vikas0vks/suvishare/releases/latest).

- **Android:** choose the `android-arm64.apk` build for most modern phones. A universal APK is also provided.
- **Windows:** run the `windows-x64-setup.exe` installer and keep the private-network firewall option enabled.
- **Linux:** install the `linux-amd64.deb`, or unpack the portable `linux-x64.tar.gz` archive.

Every release includes SHA-256 checksums. Android packages are release-signed; signing material is stored only as protected repository secrets and is never committed.

## Software updates

Suvi Share checks `vikas0vks/suvishare` GitHub Releases at most once every 24 hours by default. You can turn this off or check manually under **Settings → Software updates**.

The updater downloads nothing silently and never executes an installer. It opens the matching release asset in your browser, then Android, Windows, or Linux handles installation with its normal confirmation and security checks. Only release metadata is requested; no transferred files, contact data, analytics, or device identity are sent.

## How transfers work

```text
Device A                                             Device B
   │  UDP multicast discovery ─────────────────────────▶│
   │◀──────── HTTPS register-back ──────────────────────│
   │                                                   │
   │  prepare-upload (names, sizes, checksums) ───────▶│
   │◀──────────── accept / decline / PIN ──────────────│
   │                                                   │
   │  encrypted, streamed file bytes ─────────────────▶│
   │◀──────────── progress / resume offset ────────────│
```

App-to-app traffic uses TLS on port `53317`. Browser Web Share uses port `53318` and can be protected with an expiring session PIN. Transfers are streamed to disk instead of being loaded into memory.

## Build from source

Requirements:

- Flutter `3.47.0` or newer compatible stable release
- Dart `3.13.0` or newer compatible release
- JDK 17 and Android SDK 37 for Android builds
- Visual Studio C++ desktop tools for Windows builds
- `clang`, `cmake`, `ninja-build`, `pkg-config`, GTK 3, and Ayatana AppIndicator development packages for Linux

```bash
git clone https://github.com/vikas0vks/suvishare.git
cd suvishare/app
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
```

Run the app on a connected target:

```bash
flutter run -d <device-id>
```

Test the protocol library separately:

```bash
cd packages/suvi_core
dart pub get
dart analyze
dart test
```

Release signing is intentionally fail-closed. Android release builds require a local `app/android/key.properties` and keystore; both are ignored by Git. The tagged GitHub workflow receives the same values through protected Actions secrets.

## Project layout

```text
app/                    Flutter application and platform runners
packages/suvi_core/     Pure Dart protocol, discovery, server, and client
packaging/windows/      Windows installer source and build script
packaging/linux/        Linux package source and build script
.github/workflows/      Verification and tagged-release automation
```

## Security model

- TLS identity fingerprints are generated and stored locally.
- Trusted-device actions require verified peer identity.
- Session and per-file tokens are random, sender-bound, and invalidated on cancel.
- Filenames are sanitized and final paths are constrained to the selected save directory.
- Metadata, request counts, file sizes, and concurrent sessions are bounded.
- Web Share offers expire and may require a fresh session PIN.
- GitHub update responses are size-bounded and only trusted HTTPS release links are accepted.

Please report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## License

Suvi Share is available under the [MIT License](LICENSE).

<div align="center">
  <sub>Designed and developed by <a href="https://github.com/vikas0vks">vikas0vks</a>.</sub>
</div>
