# Omacut

## macOS community fork

This fork adds a native macOS application to [omacom/omacut](https://github.com/omacom/omacut).

**[Download the compiled macOS app](https://github.com/geekhunger/omacut/releases/latest)**

- Apple Silicon (arm64), macOS 26 or later. Intel Macs are not supported by this binary.
- Qt, FFmpeg and FFprobe are included; Homebrew is not required to run the app.
- Native macOS open/save dialogs, export-quality selection and opening videos from Finder.
- Uses macOS video acceleration for preview where supported.
- Community build; not an official upstream release. Updates are manual.

### Install on macOS

Download `Omacut-0.7.2-macos-arm64.zip` from Releases, unzip it and drag `Omacut.app`
to Applications. Alternatively, open the DMG and drag the app to Applications.

This build is ad-hoc signed, **not Apple Developer ID signed or notarized**.
macOS may block its first launch. After trying to open it, use
**System Settings → Privacy & Security → Open Anyway** and confirm the launch.
See [Apple's instructions](https://support.apple.com/en-us/102445).

The release also includes SHA-256 checksums and a separate archive of the
matching third-party sources, patches and build formulas.

### Build and package on macOS

Install Xcode Command Line Tools and the build dependencies:

```sh
brew install qtbase qtdeclarative qtmultimedia qtsvg qtquicktimeline ffmpeg
./bin/build
./bin/test
./bin/package-macos
./bin/collect-macos-sources
codesign --force --deep --sign - dist/Omacut.app
codesign --verify --deep --strict dist/Omacut.app
```

`bin/package-macos` creates `dist/Omacut.app`, bundles dynamic dependencies,
rewrites their load paths, verifies that they resolve inside the app or to
macOS system libraries, and applies an ad-hoc signature.
`bin/collect-macos-sources` downloads and verifies sources matching the installed
dependency versions and adds their license notices; re-sign after this step.
Use the release's pinned source manifest and formulas to reproduce dependency
versions rather than assuming a future `brew install` produces the same build.
`./bin/release-macos` runs the packaging and source steps and creates the ZIP,
DMG, third-party source archive and checksums in `dist/`.

Omacut's own source remains MIT licensed. The downloadable application also
includes GPL/LGPL components; see
[third-party notices](packaging/THIRD-PARTY-NOTICES.txt) and the source archive.

---

A dead-simple video editor. Open a video, trim either end, split it into clips and cut pieces out, add more videos and put the clips in any order, preview the result, and export. On Omarchy, the interface follows your theme's accent color.

Built using **Qt Quick (QML)** UI with the Material style — the same Qt stack Quickshell builds on — and **ffmpeg** for the cut. The C++ side compiles to a single executable; the QML is embedded in it via Qt resources.

<img width="3227" height="3227" alt="screenshot-2026-06-23_15-20-40" src="https://github.com/user-attachments/assets/c76047c8-618f-4c1c-91f9-e7024c4f953b" />

## Editing

The timeline shows your clips back to back, in the order they play, each framed with a handle at both ends over its own filmstrip. Whatever isn't in a clip is cut.

- **Double-click a clip** to split it there.
- **Drag a handle** to trim that clip. A trimmed clip can grow back into its video, up to either end.
- **Double-click the line** between two pieces of the same stretch of video to join them again.
- **Hold a clip, then drag it** to move it before or after the others.
- **Hover a clip** and click its **×** to remove it.
- **Click +** to add another video after the clip under the playhead.

Handles catch on neighbouring clip edges and the playhead.

## Hotkeys

- *Space*: Start/stop video playback.
- *0–9*: Jump to 0%–90% of the edit.
- *Left/Right*: Move the playhead by 1 second.
- *Shift+Left/Right*: Move the playhead by 5 seconds.
- *Alt+Left/Right*: Move the playhead by 0.2 seconds.
- *[ / ]*: Jump to the previous / next clip edge.
- *S*: Split the clip at the playhead.
- *X, Delete*: Remove the clip under the playhead.
- *Alt+[ / Alt+]*: Move the clip under the playhead earlier / later.
- *Ctrl+Space*: Move the start of the clip under the playhead to the playhead.
- *Alt+Space*: Move the end of the clip under the playhead to the playhead.
- *Ctrl+Z / Ctrl+Shift+Z*: Undo / redo.
- *Z*: Zoom to the clip under the playhead for fine tuning (Z again zooms back out).
- *F*: Save the frame under the playhead as a PNG next to its video.
- *Ctrl+O*: Open a new file to edit.
- *Ctrl+Shift+O*: Add a video after the clip under the playhead.
- *Ctrl+S*: Export the current edit.
- *Q*: Quit (asks first if the edit hasn't been exported).
- *?*: Show the hotkeys in the app.

## Install

Install via the Omarchy Package Repository via the `omacut` package. It's installed by default in new installations of Omarchy (from Quattro forward).

## Requirements

- `xdg-desktop-portal` and a portal backend for the file picker
- `ffmpeg` and `ffprobe` on your PATH (used at runtime)

Exports are always written as MP4 files, regardless of the input video's container. The export dialog offers Original/1080p/720p quality — never upscaling, and always preserving the aspect ratio. When clips come from different videos, the export takes the frame size of the first clip's video; clips of another shape are letterboxed into it, and videos without sound get silence.

## Build

Uses Qt's own build tool, `qmake6` (no cmake needed):

```bash
./bin/build
```

This produces a single `omacut` binary in `build/`.

Requirements:

- A C++17 compiler and Qt6: `qt6-base`, `qt6-declarative` (Qt Quick + Controls),
  `qt6-multimedia`

## Test

```bash
./bin/test
```

## License

MIT. See `LICENSE`.
