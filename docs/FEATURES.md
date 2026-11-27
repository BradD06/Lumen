# Что уже есть в приложении

Читать этот файл вместо того, чтобы перечитывать чат. Каждый PR, который добавляет видимую функцию, добавляет сюда строку: что умеет, на каких системах, где код.

| Функция | Системы | Где в коде |
|---|---|---|
| Приложение «Lumen» с иконкой из Lumen_exemple | Все четыре | `assets/icon/`, `flutter_launcher_icons.yaml`; на Mac свои PNG в `macos/Runner/Assets.xcassets/AppIcon.appiconset` |
| Тема «Графит»: тёмный фон с серыми свечениями, стеклянные карточки, шрифт Onest | Все четыре | `lib/theme/graphite.dart` (цвета), `lib/theme/glass.dart` (`Glass`, `GlowBackground`), `assets/fonts/` |
| Плавающий остров внизу с пятью разделами: Главная, Библиотека, Каталог, Добавить, Голоса | Все четыре | `lib/shell/island.dart`, `lib/shell/tabs.dart`, `lib/shell/app_shell.dart` |
| Профиль — кружок в левом верхнем углу (открытый белый) | Все четыре | `lib/shell/profile_button.dart` |
| Раздел «Каталог» (книги, заранее добавленные в приложение): пока заглушка | Все четыре | `lib/screens/catalog_screen.dart` |
| Открытый раздел — белый кружок над островом с вырезом под ним; при переключении (мышью, касанием или ⌘1…⌘5) кружок с вырезом плавно едет по острову, значок раздела уходит в кружок | Все четыре | `lib/shell/island.dart` (`NavIsland`, `IslandMetrics`, `notchedIsland`) |
| Клавиши ⌘1…⌘5 (на Windows Ctrl) — разделы острова, ⌘O — «Добавить книгу», ⌘, — профиль и настройки; подсказка с клавишей при наведении, белая рамка фокуса | Mac, Windows (и клавиатура на iPad) | `lib/shell/app_shell.dart`, `lib/shell/island.dart` |
| Пустые экраны разделов с подсказкой, что там будет; приветствие и дата по-русски на главной | Все четыре | `lib/screens/` |
| На Mac приложение тянется под заголовок окна, три кнопки окна лежат в его полосе | Mac | `macos/Runner/MainFlutterWindow.swift` |
| GitHub проверяет каждый PR: формат, анализ, тесты, сборка Android, Windows, macOS и iOS | — | `.github/workflows/ci.yml` |

## Как устроен код

Приложение — Flutter-проект в корне (`lib/` — экраны), логика — в отдельных пакетах `packages/` (Dart workspace, один `flutter pub get` в корне). Зависимости только вниз, это проверяет `test/layers_test.dart`:

```
экраны (lib/) → lumen_player → lumen_voice → lumen_core
              → lumen_storage → lumen_core
```

| Пакет | Что там | Сейчас |
|---|---|---|
| `lumen_core` | Модели и чистая логика, ни от чего не зависит | `Book` (один диктор: `narratorVoiceId`), `Chapter`, `Line` (кусок текста с `speaker` и `emotion`; голос один, персонажи различаются интонацией), `Emotion`, `TextRange` (места в UTF-16) |
| `lumen_voice` | Озвучка: сервер голоса, фразы, кеш, время слов | `ServerLink` (адрес и ключ из ссылки `https://…/#key=…`, пути `/v1/voices`, `/v1/speak`, `/health`), `ServerState` («не отвечает» и «нет интернета» — разные состояния). Ядро — этап 1 |
| `lumen_storage` | Хранилище книг | `BookStore` и `MemoryBookStore`. База — этап 2 |
| `lumen_player` | Плеер: голос и фоновая музыка — две дорожки | `AudioMix` (громкость музыки, приглушение под голосом). Плеер — этап 3, музыка — этап 6 |

Проверить у себя: `flutter test` (приложение) и `dart test` в папке пакета. CI держит Flutter 3.50.1 (`FLUTTER_VERSION` в `ci.yml`).
