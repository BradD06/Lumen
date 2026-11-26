# Lumen

Lumen turns text books into audiobooks with a neural voice (Qwen3-TTS): one narrator reads the whole book and gives each character their own intonation, with optional calm background music. Built with Flutter for macOS, iOS, Windows and Android.

## Features

- Runs on macOS, iOS, Windows and Android with the app icon from Lumen_exemple.
- «Графит» look: dark graphite background with soft grey glows, frosted-glass cards, Onest font.
- Floating glass island at the bottom with five sections: Home, Library, Add book, Voices, Profile. ⌘1…⌘5 (Ctrl on Windows) switch sections.
- CI checks formatting, analysis and tests and builds all four platforms on every pull request.

The plan is in [docs/ROADMAP.md](docs/ROADMAP.md) (in Russian), and what is done goes to [docs/FEATURES.md](docs/FEATURES.md).

## Run

```sh
flutter pub get
flutter run -d macos   # or: -d windows, an iOS simulator, an Android device
flutter test
```

The voice server lives in [lumen-voice-server](https://github.com/BradD06/lumen-voice-server).
