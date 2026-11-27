# Как установить и запустить Lumen

Пошагово: как подготовить Mac и Windows-ПК, забрать свежий код и запустить приложение на Mac, iPhone, Windows и Android. Команды можно копировать целиком.

Проект использует Flutter **3.50.1** (та же версия, что в проверках на GitHub, см. `.github/workflows/ci.yml`). Проверить свою: `flutter --version`.

## Где лежит код

| Компьютер | Папка |
|---|---|
| Mac | `~/Developer/Lumen` |
| Windows | `C:\dev\Lumen` |

Код переносится между компьютерами только через GitHub (репозиторий `BradD06/Lumen`), не через iCloud: iCloud делает копии файлов вида «файл 2» и ломает сборку. Не кладите проект в `~/Desktop` или `~/Documents` на Mac.

Первый раз (если папки ещё нет):

```sh
# Mac
mkdir -p ~/Developer && cd ~/Developer
git clone https://github.com/BradD06/Lumen.git
```

```powershell
# Windows (PowerShell)
mkdir C:\dev -Force; cd C:\dev
git clone https://github.com/BradD06/Lumen.git
```

## Забрать свежую версию

Каждый раз перед запуском, на любом компьютере, в папке проекта:

```sh
git checkout -f main
git pull
flutter pub get
```

Что делают эти команды:

- `git checkout -f main` переключает папку на основную версию приложения (`main`). Если раньше вы смотрели чью-то ветку (например, PR до мёржа), это вернёт вас на `main`. Флаг `-f` выбрасывает ваши локальные изменения в файлах проекта, например служебный файл `.DS_Store`, который Finder сам создаёт в папках. Без `-f` git отказывается переключаться, пока такие файлы «изменены». Свои правки в коде вы руками не делаете, так что терять нечего.
- `git pull` скачивает с GitHub всё, что смёржили с прошлого раза.
- `flutter pub get` докачивает библиотеки, если они поменялись.

Чтобы посмотреть PR до мёржа: `git fetch origin` и `git checkout -f имя-ветки` (имя ветки написано в PR вверху). Потом обратно: `git checkout -f main`.

## Mac: подготовка (один раз)

1. **Xcode** из App Store. После установки в Терминале:
   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   sudo xcodebuild -license accept
   ```
2. **Homebrew** (если ещё нет): команда с сайта https://brew.sh.
3. **Инструменты:**
   ```sh
   brew install git gh cocoapods
   brew install --cask flutter android-studio
   ```
   CocoaPods нужен для iPhone и Mac, как только в приложении появятся плагины (звук, хранилище ключа).
4. **Android Studio** (нужна только для Android): откройте её, пройдите мастер с вариантом **Standard**, он скачает Android SDK. Затем **Settings → Languages & Frameworks → Android SDK → вкладка SDK Tools**, отметьте **Android SDK Command-line Tools (latest)**, нажмите Apply. Потом в Терминале:
   ```sh
   flutter doctor --android-licenses   # на все вопросы отвечайте y
   ```
5. **Проверка:** `flutter doctor`. Зелёные галочки нужны у Flutter, Xcode и (если нужен Android) Android toolchain. Пункты Chrome и Visual Studio на Mac можно не замечать.

## Mac: запуск

```sh
cd ~/Developer/Lumen
flutter run -d macos
```

Первая сборка идёт несколько минут, потом быстрее. Пока приложение запущено из Терминала, клавиша `r` подхватывает изменения кода без перезапуска, `q` закрывает.

## iPhone

Нужен Mac с Xcode и кабель (или iPhone в той же Wi-Fi, после первого запуска по кабелю).

1. **Режим разработчика на iPhone:** Настройки → Конфиденциальность и безопасность → Режим разработчика → включить, телефон перезагрузится. Пункт появляется, когда iPhone хоть раз подключён к Mac с открытым Xcode.
2. **Подпись (один раз):**
   ```sh
   cd ~/Developer/Lumen
   open ios/Runner.xcworkspace
   ```
   В Xcode слева выберите **Runner** → цель **Runner** → вкладка **Signing & Capabilities**. В поле **Team** выберите свой Apple ID (если пусто: Xcode → Settings → Accounts → «+» → Apple ID). Если Xcode пишет, что идентификатор `io.github.bradd06.lumen` занят, допишите в **Bundle Identifier** свой хвост, например `io.github.bradd06.lumen.brad`.
3. **Запуск** (iPhone подключён и разблокирован):
   ```sh
   flutter devices          # iPhone должен быть в списке
   flutter run --release    # если устройств несколько: flutter run --release -d <id iPhone>
   ```
   `--release` нужен, чтобы приложение открывалось и без Mac: отладочная сборка на iPhone запускается только из Xcode или Терминала.
4. **Доверие разработчику:** при первом открытии iPhone скажет «Ненадёжный разработчик». Настройки → Основные → VPN и управление устройством → ваш Apple ID → Доверять.

Ограничение бесплатного Apple ID: установленное так приложение работает **7 дней**, потом его нужно снова запустить командой из шага 3. Платная программа Apple Developer ($99 в год) снимает это ограничение и нужна для TestFlight и App Store.

## Windows: подготовка (один раз)

1. **Git:** https://git-scm.com/download/win (настройки установщика по умолчанию).
2. **Flutter:** скачайте архив Flutter для Windows с https://docs.flutter.dev/get-started/install/windows и распакуйте так, чтобы получилось `C:\src\flutter` (внутри лежит папка `bin`). Не кладите его в `C:\Program Files`: там нужны права администратора.
3. **Добавить Flutter в PATH** (PowerShell, без прав администратора):
   ```powershell
   [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\src\flutter\bin", "User")
   ```
   **Закройте и откройте PowerShell заново** (и VS Code, если он был открыт), иначе новый PATH не подхватится. Проверка: `flutter --version`.
4. **Visual Studio 2026 Community** (не путать с VS Code): https://visualstudio.microsoft.com. В установщике отметьте нагрузку **«Разработка классических приложений на C++» (Desktop development with C++)**. Справа должны быть отмечены: **MSVC … build tools**, **C++ CMake tools for Windows**, **Windows 11 SDK** (или Windows 10 SDK). Если Visual Studio уже стоит: запустите Visual Studio Installer → «Изменить» и добавьте эту нагрузку.
5. **Проверка:** `flutter doctor`. Нужна зелёная галочка у **Visual Studio — develop Windows apps**.

## Windows: запуск

```powershell
cd C:\dev\Lumen
flutter run -d windows
```

**Без установки Flutter:** готовую сборку собирает GitHub при каждом PR и мёрже. Откройте https://github.com/BradD06/Lumen/actions, выберите последний зелёный запуск CI, внизу в **Artifacts** скачайте **lumen-windows**, распакуйте zip и запустите `lumen.exe` (остальные файлы рядом с ним не удаляйте). Сборки хранятся 7 дней.

## Android

Подготовка: на Mac это шаг 4 из «Mac: подготовка». На Windows установите Android Studio с https://developer.android.com/studio и сделайте то же: мастер Standard, **SDK Command-line Tools**, `flutter doctor --android-licenses`.

1. **Отладка по USB на телефоне:** Настройки → О телефоне → 7 раз нажать «Номер сборки» (появится «Вы стали разработчиком»). Затем Настройки → Система → Для разработчиков → **Отладка по USB** → включить. Подключите кабель и на телефоне разрешите отладку для этого компьютера.
2. **Запуск:**
   ```sh
   flutter devices     # телефон должен быть в списке
   flutter run         # если устройств несколько: flutter run -d <id телефона>
   ```
   Для постоянной установки без компьютера: `flutter run --release`.

**Без компьютера:** в GitHub Actions (как для Windows выше) есть артефакт **lumen-android** с файлом `app-debug.apk`. Скачайте его на телефон и откройте; Android попросит разрешить установку из этого источника.

Эмулятор вместо телефона: Android Studio → Device Manager → Create device, запустите его, затем `flutter run`.

## Проверки перед PR

Это делает и GitHub, но можно запустить у себя (в папке проекта):

```sh
dart format --line-length 100 lib test packages
flutter analyze
flutter test
```

## Если что-то не работает

**`flutter` не является внутренней или внешней командой** (Windows) или **`command not found: flutter`** (Mac).
Windows: проверьте, что есть файл `C:\src\flutter\bin\flutter.bat`, повторите шаг 3 из «Windows: подготовка» и обязательно откройте PowerShell заново. Посмотреть PATH: `$env:Path -split ';'`. Mac: `brew install --cask flutter`, затем новое окно Терминала.

**`error: Your local changes to the following files would be overwritten by checkout`** (часто про `.DS_Store`).
Это служебный файл Finder. Используйте `git checkout -f main`, он выбросит такие изменения. Сейчас `.DS_Store` уже в `.gitignore` и в репозитории не хранится, так что ошибка была только со старыми версиями.

**`Unable to find suitable Visual Studio toolchain`** или ошибки CMake / MSVC при `flutter run -d windows`.
Не хватает частей Visual Studio. Visual Studio Installer → «Изменить» → нагрузка «Разработка классических приложений на C++» с MSVC, CMake tools и Windows SDK. После установки откройте PowerShell заново и проверьте `flutter doctor`.

**`cmdline-tools component is missing`** или **`sdkmanager not found`** при `flutter doctor --android-licenses`.
В Android Studio → Settings → Android SDK → SDK Tools отметьте **Android SDK Command-line Tools (latest)** и нажмите Apply. Затем повторите команду.

**`Android license status unknown`** — выполните `flutter doctor --android-licenses` и ответьте `y` на всё.

**iPhone не виден в `flutter devices`.**
Телефон разблокирован, на нём нажато «Доверять этому компьютеру», включён Режим разработчика. Откройте Xcode → Window → Devices and Simulators: там видно, готов ли телефон.

**`No profiles for 'io.github.bradd06.lumen' were found`** или «идентификатор недоступен».
Не выбран Team в Signing & Capabilities, или идентификатор занят: допишите хвост к Bundle Identifier (шаг 2 раздела «iPhone»).

**Приложение на iPhone перестало открываться через неделю.**
Закончились 7 дней бесплатной подписи. Подключите iPhone и снова выполните `flutter run --release`.

**`CocoaPods not installed`** — `brew install cocoapods`, затем снова `flutter run`.

**Xcode просит принять лицензию** или `xcodebuild` выдаёт ошибку при первом запуске — `sudo xcodebuild -license accept` и `sudo xcodebuild -runFirstLaunch`.

**Странные ошибки сборки после обновления** — очистка и повтор:
```sh
flutter clean
flutter pub get
flutter run -d macos   # или ваша платформа
```
