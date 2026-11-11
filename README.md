# Shiyi Translator (拾译)

[English](README.md) | [简体中文](README.zh-CN.md)

A Flutter desktop translator for Linux, Windows, and macOS. Current version: 0.3.7. Validation currently focuses on KDE Wayland.

## About the name

**Shiyi** is the pinyin of 拾译. 拾 means picking up words and phrases encountered while reading; 译 means understanding them through translation. Select text and press a shortcut to see its translation nearby, then continue reading.

**Pick up words. Understand the world.**

The application and desktop menu use “拾译 / Shiyi Translator”. The internal application ID and data directory retain their original identifiers, so existing service settings, credentials, and history remain available after updates.

## Features

- Translate typed text, automatically detect the source language, select the target language, and copy results.
- Four API types: Chat Completions-compatible, DeepL, LibreTranslate, and Baidu General Translation.
- Configure multiple instances of each API type. Services run concurrently, and individual failures do not interrupt other results.
- Drag service cards by their left handles to reorder them. Order is saved automatically and applied to both the main window and popup, regardless of response speed. Editing a service preserves its position.
- Service cards show enabled status, API type, and model. Endpoint addresses appear only in the editor. Grouped settings and fixed test/save controls support small windows and dark mode.
- Optional SSE streaming for compatible APIs.
- Cancellation, retries, a 45-second timeout, and an in-memory cache. Older requests cannot overwrite newer results.
- Up to 100 local history entries, with options to disable history or clear it.
- System tray, background operation after closing the window, an independent translation popup, always-on-top mode, and dark mode.
- Optional launch at login, starting quietly in the tray. The setting reads and manages the operating system's startup entry directly.
- Shortcuts open only the translation popup, preserving the main window's draft, page, and dimensions.
- Popup sections for source text, language selection, and service results, with copy, editing, and collapse controls.
- Popup height adapts to its content. Long content scrolls when it exceeds the available screen height.
- Closing the popup or pressing Escape hides it. An unpinned popup hides when it loses focus; the main process keeps running.
- Translate selected text with a shortcut, with an explicit indication when clipboard fallback is used.
- Single-instance operation and `--selection` / `--clipboard` commands for desktop shortcuts.

This version does not include OCR, automatic floating buttons after text selection, no-focus popups, a third-party plugin marketplace, or cloud sync.

## Development requirements

Development environment: Flutter 3.47.7 / Dart 3.13.5. Dart is included with Flutter.

Manjaro / Arch:

```bash
sudo pacman -S --needed base-devel clang cmake ninja pkgconf gtk3 libsecret libayatana-appindicator wl-clipboard
```

Ubuntu:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev libsecret-1-dev libayatana-appindicator3-dev
```

Selection capture requires `xclip` on X11 or `wl-clipboard` on Wayland. Global shortcuts use the XDG GlobalShortcuts Portal and require a suitable desktop backend, such as `xdg-desktop-portal-kde` on KDE.

Windows builds require Windows and Visual Studio with the “Desktop development with C++” workload. macOS builds require a Mac, Xcode, and the package manager required by Flutter plugins. Selection capture on macOS requires permission under Privacy & Security → Accessibility. App Sandbox is currently disabled for the macOS desktop build; this is not a Mac App Store distribution configuration.

## Run from source

```bash
flutter pub get
flutter run -d linux
```

Add a provider under “翻译服务” (Translation Services), then enter its endpoint, model (for compatible APIs), and API key. No credentials are bundled, and translation text is not automatically sent to public translation websites.

When adding or editing a provider, “测试连接” (Test Connection) translates `Hello, world!` from English to Simplified Chinese using the current form values. It shows the translation, elapsed time, or failure reason. Testing does not require saving and does not add history. You can cancel a test; changing the form clears its previous result. A display name is required to save, but not to test.

Drag a provider's left handle to change its order. Existing results reorder immediately while active translations continue. The order is saved locally and restored after restarting.

| API type | Example endpoint | Notes |
| --- | --- | --- |
| Chat Completions-compatible | `https://your-provider.example/v1` | Use the provider's model ID; custom gateways and local models with a compatible API are supported |
| DeepL Free | `https://api-free.deepl.com` | Requires a DeepL API Free key |
| DeepL Pro | `https://api.deepl.com` | Requires the corresponding Pro key |
| LibreTranslate | `http://localhost:5000` | Connect to your own instance; supply a key if required |
| Baidu Translation | `https://fanyi-api.baidu.com` | Requires an APP ID, secret, and access to Baidu General Translation |

Baidu requests use POST form data containing the APP ID, source text, random salt, and an MD5 signature. The secret stays in the system credential store; it is not sent as a plain-text request field or included in popup communication. Japanese, Korean, French, and Spanish are mapped to Baidu language codes. Segmented results are joined in order. Requests exceeding 6,000 UTF-8 bytes prompt you to split the text instead of truncating it. Authentication, signature, rate-limit, and balance errors have specific messages.

Reference: [Baidu General Translation documentation](https://fanyi-api.baidu.com/doc_bd/21).

You can enter a base endpoint or a full `/chat/completions`, `/v2/translate`, `/translate`, or `/api/trans/vip/translate` URL. Do not put credentials or query parameters in endpoint URLs. Requests use Dart HttpClient's environment-based proxy configuration.

API keys are stored in the system credential store. Linux requires a running Secret Service, such as one provided by KWallet or GNOME Keyring. Credential storage failures are reported without falling back to plain-text files. Local services that do not need a key can leave it blank.

## English pronunciation

English source text and translations have a speaker button in both the main window and popup. Click to read aloud; click again to stop. When the source language is set to automatic detection, the control appears only for English-only text. English words automatically get phonetic transcriptions from the [Free Dictionary API](https://dictionaryapi.dev/): the word is sent to that service after 600 milliseconds without input changes. Sentences support read-aloud, but not full-sentence phonetic transcriptions. Transcriptions are cached only in memory, and lookup failures do not affect translation.

Read-aloud uses system speech tools rather than translation APIs. Linux requires `espeak-ng` (or `espeak`) and working audio output. Windows uses an installed English system voice; macOS uses the Samantha English voice. Missing tools or playback failures display an error.

## Launch at login

Enable “开机自启动” (Launch at Login) under “偏好设置 → 启动与后台” (Preferences → Startup & Background). It is disabled by default and manages only the current user's Shiyi startup entry. At the next desktop login, `--autostart` starts the app with the main window hidden and tray/shortcut translation available. If the tray is unavailable, the main window appears. An existing instance prevents startup from reopening a window or capturing selected text.

Disabling the setting removes the startup entry without stopping the running application. Its state comes directly from the operating system configuration rather than a separate stored boolean.

On Linux, the app checks whether the desktop actually registered its tray icon. If registration fails or the tray disappears, the main window is shown. Every 10 seconds, the app cleans up failed tray objects, attempts to recreate the tray, and checks registration. Recovery clears the tray warning. If “keep running in the tray after closing” is enabled but the tray is unavailable, the window stays visible; you can explicitly quit from Preferences.

- Linux: `$XDG_CONFIG_HOME/autostart/dev.justtranslator.just_translator.desktop`, defaulting to `~/.config/autostart/`, following the [XDG Autostart specification](https://specifications.freedesktop.org/autostart/latest/).
- Windows: the current user's [Run registry key](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys), using the value name `ShiyiTranslator`.
- macOS: a per-user [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) at `~/Library/LaunchAgents/dev.justtranslator.justTranslator.autostart.plist`.

Autostart tests create and remove entries in temporary directories without enabling startup on the development machine. Native Windows and macOS integrations still require building and validation on their respective systems.

## Translate selected text

The default requested shortcut is `Ctrl + Alt + Space` (Control + Option + Space on macOS). Linux registers it through the desktop Portal, which may show a permission or configuration dialog. The actual binding is determined by system settings.

1. Select text in another application.
2. Press the global shortcut.
3. The app captures the selection and opens the independent translation popup. The main window remains unchanged.

Linux Wayland uses the PRIMARY selection; X11 uses xclip; Windows uses UI Automation; macOS uses the Accessibility API. Selection capture depends on the target application and desktop environment and is not guaranteed in every application. If capture fails, the app tries the clipboard and labels the source below the input. You can also copy text manually and invoke clipboard translation.

If Portal shortcuts are unavailable, add custom shortcuts in KDE System Settings with these commands:

```bash
/absolute/path/to/just_translator --selection
/absolute/path/to/just_translator --clipboard
```

Launching the program again forwards the action to the existing instance. Internal IPC binds only to a random localhost port and validates a random token; it does not expose a public translation API.

Always-on-top behavior and focus activation on Wayland depend on the window manager and may differ from X11. The translation popup is a separate window; it does not resize or bring the main window to the front. It appears near the pointer captured when translation was invoked, flips left or upward when needed, and stays within that monitor's work area.

## Build and install

```bash
flutter build linux --release
```

The executable is at `build/linux/x64/release/bundle/just_translator`. Distribute the entire `bundle` directory.

Optionally install into the current user's directory and create an application menu entry without changing system directories:

```bash
bash tools/install-linux.sh
```

The desktop entry uses the same Desktop ID as the application ID so desktop Portals can recognize it. Windows and macOS projects include native shortcut and selection-capture integrations, but must be built and validated on their respective platforms.

## Linux installation packages

Linux packaging produces both `.deb` and Arch `.pkg.tar.zst` installers for x86_64. They install into `/opt/shiyi-translator` and add a command, icon, and application menu entry. Packages declare `espeak-ng` as a dependency for English read-aloud; `wl-clipboard` and `xclip` are recommended or optional dependencies for selection capture. Saving API keys still requires a running desktop Secret Service.

On Ubuntu, run from the download directory, substituting the actual package version:

```bash
sudo apt install ./shiyi-translator_0.3.7-11_amd64.deb
```

On Arch Linux:

```bash
sudo pacman -U ./shiyi-translator-0.3.7-11-x86_64.pkg.tar.zst
```

After installation, open “拾译” / “Shiyi Translator” from the application menu, or run `just_translator`. Fully quit the old instance before upgrading. Uninstall with `sudo apt remove shiyi-translator` or `sudo pacman -R shiyi-translator`; user settings and history are retained.

Package an existing local build:

```bash
python3 tools/package-linux.py
```

Packaging requires Python 3, `dpkg-deb`, `bsdtar`, `zstd`, and `readelf`. On Ubuntu, install the `dpkg`, `libarchive-tools`, `zstd`, and `binutils` packages. On Arch, install `dpkg`, `libarchive`, `zstd`, and `binutils`. Output goes into `dist/`. The version comes from `pubspec.yaml`; for example, `0.3.7+11` becomes package version `0.3.7-11`.

Packages scan the build output to declare the minimum glibc version. Build on a system old enough for your intended targets. The release workflow builds on Ubuntu 22.04; packages built locally on Arch are not guaranteed to run on Ubuntu 22.04. Check the dependencies declared in the package.

## Publish a GitHub Release

Pushing a `v*` version tag triggers static analysis and tests, followed by Linux, Windows, and macOS builds. After all three platforms succeed, the workflow creates the corresponding GitHub Release, generates release notes, and uploads the packages. The release becomes public after uploading. Rerunning the workflow for the same tag updates assets with matching names.

Before publishing, update the version in `pubspec.yaml`, commit and push the code, then tag that commit. For example, for version `0.3.7+11`:

```bash
git tag v0.3.7
git push origin v0.3.7
```

Release assets include `shiyi-translator-linux-x64.tar.gz`, `shiyi-translator-windows-x64.zip`, and `shiyi-translator-macos.zip`. Linux also includes `shiyi-translator_VERSION-BUILD_amd64.deb` and `shiyi-translator-VERSION-BUILD-x86_64.pkg.tar.zst`. For the `.tar.gz` package, keep the complete `bundle` directory and install `espeak-ng` separately. Windows and macOS currently ship unsigned application archives.

Ordinary `main` pushes, pull requests, and manual runs produce Actions Artifacts without publishing a Release. Publishing uses the built-in GitHub Actions token; only the release job has repository contents write permission. No additional secret is required.

## Data storage

`settings.json` is stored in the system application data directory. On Linux this is usually `$XDG_DATA_HOME/dev.justtranslator.just_translator/`, or `~/.local/share/dev.justtranslator.just_translator/` when `XDG_DATA_HOME` is unset. It contains provider settings, preferences, and optional translation history, but no API keys. Keys are stored separately by provider ID in the system credential store. Caches exist only in memory.

## Validation

```bash
flutter analyze
flutter test
flutter build linux --release
flutter test integration_test/desktop_smoke_test.dart -d linux
```

Unit tests use temporary local HTTP servers to verify real requests, Baidu signatures, form encoding, language mappings, and streaming parsing without paid API keys. Integration tests use test settings and fixed translations to verify the interface. Screenshots are saved to `build/screenshots/`; real translation services are not called.

## Source layout

- `lib/models.dart`: provider settings, results, and history data.
- `lib/services/translation_service.dart`: the four API protocols, Baidu signing, SSE, timeouts, and cancellation.
- `lib/app_controller.dart`: concurrent translation, caching, history, and state.
- `lib/services/selection_service.dart`: platform selection capture and clipboard fallback.
- `lib/services/shortcut_service.dart`: Linux Portal and native shortcut integration.
- `lib/services/instance_service.dart`: single-instance operation and local command forwarding.
- `lib/services/storage_service.dart`: atomic settings writes and system credential storage.
- `lib/app.dart` and `lib/widgets/`: user interface.
- `windows/runner/` and `macos/Runner/`: native selection capture and global shortcuts.

## Independent popup

Shortcuts, tray selection capture, and `--selection` / `--clipboard` open only the translation popup. The popup button at the top right of the main window sends the current source text to it. A cold start for selection capture also keeps the main window hidden. The popup's settings button opens the Translation Services page in the main window.

The popup is an independent native window. The main process continues to manage translation requests, history, and credentials. Communication uses authenticated local IPC and does not transmit API keys or history. Repeated capture reuses the popup, and quitting the application terminates it.

Relevant files: `lib/popup.dart` for the interface and window behavior, and `lib/services/popup_service.dart` for state and window lifecycle.

## Positioning near the pointer

When the shortcut is invoked, the app first captures the pointer position and the monitor's work area, then retrieves the selected text and displays the popup. Positioning uses logical pixels, supports monitors with negative coordinates, and flips the popup near screen edges. Windows, macOS, and X11 use the screen plugin. KDE Wayland uses a temporary KWin script that matches only this application's popup process; it does not modify other windows or install global window rules. The script is unloaded after positioning updates or when the app exits. You can still drag the popup manually. Other Wayland desktops may not support application-controlled positioning; when the location cannot be obtained, the window manager's default placement is retained.
