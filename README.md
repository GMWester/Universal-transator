# Universal Translator

An offline translator, dictionary, grammar reference and character chart for all languages, with
speech from [IPAReader](https://github.com/GMWester/IPAReader).

One Flutter code base builds for **Windows (x64 and ARM64), Linux, macOS, iOS, Android phones and tablets, Android TV
and Android XR**. The Android builds cover new and old devices: the main APK supports Android 7.0 and
later (API 24+), and a separate *legacy* APK supports Android 5.0–6.0 (API 21–23), which includes older
Android TV boxes.

## Features

| Page | What it does |
|---|---|
| **Translate** | Translates sentences offline with a neural model (NLLB-200: 200 languages, or M2M-100: 100 languages) running on-device through ONNX Runtime. The model handles grammar and word order. For language pairs the model does not cover, the app translates word by word from Wiktionary and reorders the words using the target language's word-order rules from WALS. The result is labelled *approximate*. Text and results can be spoken. |
| **Dictionary** | A dictionary from any language to any other. It shows every Wiktionary meaning (with tags, examples, synonyms, antonyms and related words), IPA pronunciations, inflected forms and etymology, plus the translations into the chosen target language. Inflected forms ("went", "huizen") find their lemma. *Search by meaning* is a reverse dictionary. When the app language has its own Wiktionary edition installed, meanings are also shown in that language. |
| **Grammar** | *Rules*: every grammar rule known for a language (WALS + Grambank, 387 features for 3 500+ languages), grouped into sentence structure, word structure, sounds and other categories. Each rule includes its explanation and glossed example sentences. *Compare*: lines up two languages, highlights the rules where they differ, and lets you show only the differences. It also compares the forms of a word in both languages. |
| **Characters** | For the selected language: its alphabet, capital letters, extra letters, digits and punctuation (CLDR), the letters its dictionary uses, and every Unicode character of its scripts (163 scripts). Tap a character to see its code point and name and to hear it. |
| **Offline data** | Choose what to download from this GitHub repository: tick the languages you want (searchable, with sizes, *Suggested* picks English + your languages), pick the meanings language (Wiktionary edition), and press *Download selected*. The translation models are downloaded here too. Everything downloaded works offline. On first start the app offers to open this page. |
| **Settings** | Themes (light, dark with a neutral gray background, OLED black), app language, voice, speed, pitch, translation model, and updates. |

**App language.** Pick any of 424 display languages. All 8 700+ language names in the app are then
written in that language, so you can find the right language easily. Search works with the localized
name, the English name, the language's own name (autonym) or the ISO code. The interface text itself is
translated into 12 languages (English, Spanish, French, German, Dutch, Portuguese, Italian, Russian,
Chinese, Japanese, Arabic, Hindi). Other app languages use English interface text, with language names
still in the chosen language.

**Speech.** All speech goes through IPAReader, which is compiled from the git submodule into every app.
The app turns text into IPA in this order:
1. Wiktionary's IPA for the word (inflected forms included).
2. Grapheme-to-phoneme rules that the data pipeline learns automatically for every language with
   Wiktionary pronunciations.
3. A fallback table for common alphabets (Latin, Cyrillic, Greek, Armenian, Georgian, Hebrew, Arabic,
   Devanagari, Thai, kana, Hangul).

Scripts written without spaces (Chinese, Japanese, Thai and others) are segmented by
longest dictionary match.

**Offline.** Language names, grammar rules, grammar explanations and character charts are built into
the app (3.8 MB). Dictionaries and the translation model are downloaded inside the app, from this
repository's releases (`data-<edition>` for dictionaries, `model-<id>` for the mirrored translation
models). After that, everything runs without a network connection.

**Full installers.** Windows, macOS and Linux also get a *full* variant (`…-full-setup.exe`,
`…-macos-full.zip`, `…-full.AppImage`, `…-full.tar.gz`) that already contains the M2M-100 translation
model and the largest dictionaries (English first), up to GitHub's 2 GB per-file limit, so it works fully
offline right after installation. More languages can still be added from the Offline data page. A full
installation keeps updating to the full variant.

**Portable mode.** If a file named `portable.txt` is next to the program, the app keeps everything
(dictionaries, translation models, settings, temporary files) in a `user-data` folder beside it and
writes nothing to the computer, so the folder can live on a USB stick. The Windows portable zip
already contains `portable.txt`. The Windows installers have a *Portable mode* checkbox that installs
into the chosen folder without an uninstaller, registry entries or shortcuts. Portable copies update
by replacing the program files from the portable zip, and they keep `user-data`.

**Updates from inside the app.** The app checks GitHub Releases at startup, and you can also check
from Settings.

| Platform | How the update installs |
|---|---|
| Android (phone, TV, XR) | Downloads the APK and installs it through the system package installer. The APK is signed with the same key as the installed app, so it replaces the app in place with no uninstall. |
| Windows | Runs the new installer silently, then restarts the app. |
| macOS | Replaces the `.app` bundle and relaunches. |
| Linux | Replaces the AppImage or the extracted bundle and relaunches. |
| iOS | Apple only allows App Store or TestFlight updates, so the app opens the store page. |

## Project layout

```
lib/                      Flutter app (UI, dictionary, grammar, speech, translation, updater)
packages/ipareader_ffi/   FFI plugin; third_party/ipareader is the IPAReader git submodule
assets/data/              bundled offline data (built by tools/build_assets.py)
assets/config/            app_config.json: GitHub repo, data releases, translation models
tools/                    data pipeline (Wiktionary packs, bundled assets, icons, CI helpers)
installer/                Windows Inno Setup script, Linux .desktop file
.github/workflows/        CI, Release (all platforms), Offline data packs
```

## Building

```bash
git clone --recursive https://github.com/GMWester/Universal-transator
cd Universal-transator
flutter pub get
flutter run                      # or: flutter build apk / windows / macos / linux / ios
```

* Flutter 3.50.1 or newer (stable).
* ONNX Runtime (neural translation) comes from Microsoft's NuGet package, pinned by SHA-256
  (`packages/flutter_onnxruntime`, a vendored copy of the `flutter_onnxruntime` plugin). It is used on
  Android, Windows and Linux. Microsoft's iOS/macOS packages are currently not downloadable (their
  `download.onnxruntime.ai` CDN was retired), so iPhone, iPad and Mac use the dictionary-based
  translation until that is restored.
* Linux needs `libgtk-3-dev`, `libgstreamer1.0-dev` and `libgstreamer-plugins-base1.0-dev`.

## Releasing (GitHub Actions)

1. **Add the Android signing key** as repository secrets (see *Android signing key* below). The
   Release workflow builds and publishes nothing until these secrets exist.
2. **Build the offline data once** (needed before the full installers contain dictionaries): Actions → *Offline data packs* → *Run workflow*. This
   converts the Wiktionary dumps from kaikki.org into language packs and uploads them to the
   `data-<edition>` releases that the app downloads from. Run it again whenever you want fresher data.
3. **Release the app:** push a tag (`git tag v1.0.0 && git push origin v1.0.0`) or run *Release*
   manually. It builds these files and attaches them to the GitHub Release:
   * `universal-translator-android.apk` and `.aab`
   * `universal-translator-android-legacy.apk`
   * `universal-translator-windows-x64-setup.exe` / `-arm64-setup.exe`, their `-full-setup.exe` variants and `-portable.zip`
   * `universal-translator-macos.zip` and `-macos-full.zip`
   * `universal-translator-linux-x86_64.AppImage`, `-aarch64.AppImage`, their `-full` variants and the `.tar.gz` bundles
   * `universal-translator-ios-unsigned.ipa`

   The iOS file is unsigned. To install it you need your own signing (Xcode, AltStore) or the App
   Store or TestFlight. Set `iosAppStoreUrl` in `assets/config/app_config.json` once the app is
   listed.

### Android signing key

Every Android release must be signed with the same key. That is what lets the app update itself
without being uninstalled. Add these repository secrets under *Settings → Secrets and variables →
Actions*:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the keystore file, base64-encoded on one line |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |
| `ANDROID_CERT_SHA256` | optional: the certificate fingerprint. The build fails if an APK is signed with any other key. |

### Rebuilding the bundled data

```bash
tools/fetch_sources.sh data-src
python3 tools/build_assets.py --src data-src --out assets/data
```

## Data sources and licenses

See [DATA_LICENSES.md](DATA_LICENSES.md). The app is licensed under the AGPL-3.0, the same license as
IPAReader.
