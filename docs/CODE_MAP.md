# Lumen: карта кода

Где что лежит в коде, чтобы не искать заново. Сверено с кодом в `main` 20 ноября 2026 (после PR #111).

- **Читай перед началом любой работы**, вместе с [`.claude/CLAUDE.md`](../.claude/CLAUDE.md) (правила) и [`FEATURES.md`](FEATURES.md) (что уже умеет приложение). Карта отвечает на вопрос «в каком файле», FEATURES на вопрос «есть ли такая функция», CLAUDE.md на вопрос «как здесь принято».
- Пути без префикса считаются от `Packages/LumenKit/Sources/`.
- **Как вести файл:** PR, который добавляет, переносит, переименовывает или удаляет файл, модуль, экран, таблицу или миграцию, правит карту в том же PR. Мелкие правки внутри файла карту не трогают.
- Если карта и код расходятся, прав код: проверь `grep -rn "ИмяТипа" Packages/LumenKit/Sources` и поправь карту.

## 1. Быстрый поиск: «хочу поменять X»

| Что меняем | Куда идти |
|---|---|
| Запуск приложения, окно, меню Mac, открытие файлов из Finder, `lumen://` | `App/LumenApp.swift` (`LumenApp`, `LumenAppDelegate`, `AppEnvironment`: база, синк; меню `EditorCommands`, `SoundCommands`) |
| Shortcuts / Siri «быстрая заметка» | `App/QuickNoteIntent.swift` |
| Какие экраны есть (enum) | `LumenUI/RootView.swift` → `SidebarItem` |
| Что показывает пункт навигации | `RootView.detail(_:pane:)`; на iPhone `Phone/PhoneRootView.swift` (`PhoneRoute`, `PhoneTab`) |
| Заголовок вкладки / пункта | `Navigation/WorkspaceViews.swift` → `ItemTitle` |
| Остров внизу (Стол, Записки, Дела, Полка, Поиск, Создать, Ещё) | `Navigation/Island.swift` (`NavigationIsland`, `StudyRoom`), кружок с вырезом `Navigation/BubbleBar.swift` |
| Вкладки, «Назад / Вперёд», две панели | `Navigation/Workspace.swift` (`Workspace`, `WorkspaceTab`, `NavigationHistory`), `WorkspaceViews.swift`, `PaneSplit.swift`, `PaneLayout.swift` |
| Книга открывается своей вкладкой | `Workspace.opensInOwnTab` (`Navigation/Workspace.swift`), закрытие вкладки книги в `RootView.closeScreen` |
| Вкладки кружками у острова (и круглая «+») | `Navigation/IslandTabs.swift` (`IslandTabs`, `TabGlyph`, `TabContextMenu`), место слева от острова в `RootView.island`; режим `TabStripMode.island` в `ScreenOptions.swift` |
| Горячие клавиши окна (⌘[ ⌘] ⌘\ ⌘T ⌘W ⌘1…9) | `RootView.tabShortcuts` |
| ⌘K (палитра команд, поиск) | `Navigation/CommandPalette.swift`; доп. команды `RootView.paletteExtras` / `currentItemCommands`; поиск в базе `LumenStorage/Search.swift` (`searchEverything`) |
| Меню «Создать», быстрый ввод, Настройки | `Navigation/AppActions.swift` (`CreateKind`, `AppActions`, `Creator`, `CaptureField`, `CreateSheet`, `SettingsSheet`) |
| Настройки: тема, что показывать на экране, звуки, синк | `Navigation/ThemeSettings.swift` (`AppearanceSection`), `Navigation/ScreenOptions.swift`, `LumenSounds.swift` (`SoundCommands`), `SyncSetupViews.swift` (`SyncSection`) |
| Цвета, тема «Остров», анимации | `LumenThemes/Theme.swift` (`Theme.light` / `.dark`, `AppearanceMode`), `Motion.swift` (`LumenMotion`), `Components.swift`, `ThemeContrast.swift`, `CoverTinting.swift` |
| Экран «Стол» (главная) | `LumenUI/HomeView.swift`; данные `Queries.swift` → `HomeSnapshot`, `DeskNote` |
| «Записки» (входящие) и разбор по одной, Архив (корзина) | `LumenUI/InboxView.swift` (`InboxView`, `InboxTriageView`, `TrashView`); данные `InboxQuery`, `TrashSnapshot`; удаление `TrashRepository.swift` |
| «Полка»: библиотека, папки, холст | `Library/LibraryView.swift` + `LibraryView+Actions` / `+Tiles` / `+SystemMenu`, `LibraryTiles.swift`, `LibraryCompactList.swift` (iPhone); данные `LibrarySnapshot` |
| Книжные полки (корешки, перетаскивание, сортировка) | `Library/BookShelf.swift` (`BookShelf`, `BookSpine`, `BookSpineStyle`, `ShelfLayout`, `ShelfDropDelegate`), `ShelfViews.swift`, `LumenCore/ShelfSort.swift`, `ShelfDisplay.swift`; данные `ShelfQuery` / `ShelfSnapshot` |
| Заметки на полке (папки-скоросшиватели, лоток, приколотые листы) | `Library/ShelfSheets.swift` |
| «Читаю сейчас», витрина книги, лампа | `Library/ShelfReadingNow.swift`, `BookShowcase.swift`, `BookStatsCard.swift`, `StudyLamp.swift` |
| Обложка книги (своё фото, полоска на корешке) | `Library/BookCover.swift`; хранение `SourceRepository.setCustomCover` |
| Редактор заметки | `Editor/PageEditorModel.swift` (+ расширения, см. §6.6), `PageEditorView.swift`, `BlockRow.swift`, `BlockTree.swift` |
| Новый тип блока | `LumenCore/BlockType.swift` (case, название, значок) → `BlockRow.swift` (как рисовать) → `PageEditorModel+Blocks.swift`; экспорт `LumenCore/PageExport.swift`, PDF `Export/PagePDFRenderer.swift`, Markdown-вставка `LumenCore/MarkdownPaste.swift` |
| Слэш-меню, `[[` / `@` ссылки | `BlockRow.swift` (`SlashMenu`, `PageLinkMenu`), `LumenCore/MentionTrigger.swift`, `MarkdownShortcut.swift` |
| Жирный / курсив / ссылки в тексте | `LumenCore/InlineMarkup.swift`, `Editor/PageEditorModel+Format.swift`, `Editor/FormatBar.swift` |
| Листы A4 в заметке | `LumenCore/NoteSheets.swift`, `Editor/PageEditorModel+Sheets.swift`, `NoteSheetViews.swift`, `SheetLoading.swift` |
| Обложка и фон заметки | `Editor/PageCoverBand.swift`, `CoverTint.swift`, `PageBackgroundPicker.swift`, `AttachmentImage.swift` (`PageCoverView`); модель `LumenCore/Page.swift` (`CoverCrop`, `PageCover`, `PageBackground`) |
| Читалка | `Reader/ReaderModel.swift`, `ReaderView.swift` + `+Book` / `+Notes`, `ReaderChrome.swift`; движки `LumenReader/WebReader.swift`, `PDFReader.swift` |
| Новый формат книги | `LumenReader/ReadableDocument.swift` (`DocumentConverter`) + новый `*Converter.swift`; формат в `LumenCore/Source.swift` (`SourceFormat`); тип файла в `project.yml` → `info:` |
| Выделения и выписки из книги | `ReaderModel` (`highlightSelection`, `addExcerpt`, `excerptTarget`), `Reader/ReaderSelectionBars.swift`, `ExcerptDrag.swift`, `HighlightNote.swift`; хранение `SourceRepository.addHighlight`; ссылки `LumenCore/LumenLink.swift` |
| Статистика чтения | `Reader/SourceDashboardView.swift`, `ReadingOverviewView.swift`, `ReadingWidgets.swift`, `LumenCore/ReadingStats.swift`, `ReadingInsights.swift`, `LumenStorage/ReadingRepository.swift` |
| Рукописные тетради | `Drawing/NotebookView.swift`, `PencilCanvas.swift` (iOS), `MouseDrawing.swift` (Mac), `NotebookSheetStrip.swift`, `Editor/PageEditorModel+Drawing.swift`; модель `LumenCore/Notebook*.swift` |
| Базы данных, задачи | `Database/DataTableScreen.swift` (`TasksScreen` = «Дела»), `DataTableModel.swift`, `DataLayouts.swift`, `PropertyViews.swift`, `RelationViews.swift`, `FormulaEditor.swift`; логика `LumenCore/DataTable.swift`, `Formula.swift`, `DataRelation.swift`; хранение `DataTableRepository.swift` |
| Резервные копии, восстановление базы | `LumenStorage/Backup.swift`, `LumenUI/Backup/DataSafetyView.swift`, `DatabaseRecoveryView.swift` |
| Экспорт Markdown / PDF | `LumenStorage/Export.swift`, `LumenCore/PageExport.swift`, `LumenUI/Export/` |
| Синхронизация | §4 ниже |
| Всплывашки и лог | `LumenUI/Notices.swift` (`NoticeCenter`, `lumenLog`) |
| Звуки и отклик | `LumenUI/LumenSounds.swift` (`LumenSound`, `LumenSounds`) |
| Подсказки клавиш ⌘J | `Navigation/KeyHints.swift` |
| Значок приложения | `App/Assets.xcassets/AppIcon.appiconset`, исходники `docs/design/app-icon/` |

## 2. Сборка, проект, CI

| Что | Где |
|---|---|
| Xcode-проект | генерируется из `project.yml` (XcodeGen). `Lumen.xcodeproj` и `App/Info.plist` не в git. Типы документов, свои типы перетаскивания, URL-схема `lumen` в `project.yml` → `targets.Lumen.info` |
| Команды | `Makefile`: `make project` (xcodegen), `make open`, `make test` (`swift test --package-path Packages/LumenKit`) |
| Пакет и модули | `Packages/LumenKit/Package.swift`. Зависимости: GRDB 7, ZIPFoundation, SwiftMath |
| Подпись | `Config/Signing.xcconfig` → `Config/Local.xcconfig` (не в git). `Config/iCloud-*.entitlements` используются только при включённом CloudKit |
| CI | `.github/workflows/ci.yml`: «Тесты пакетов» (`swift test`), «Сборка приложения» (iOS Simulator и macOS), «UI-тесты (macOS)» (`UITests/`, цель `LumenAppUITests`). Всё на `macos-15` |
| Режим тестов | приложение с `-uiTesting`: база в памяти, без сохранения вкладок (`App/LumenApp.swift`) |

## 3. Модули

```
LumenUI ─┬─> LumenReader ─> LumenCore
         ├─> LumenSync ───> LumenStorage ─> LumenCore
         ├─> LumenStorage
         ├─> LumenThemes
         └─> LumenCore
```

| Модуль | Что внутри | Чего там быть не должно |
|---|---|---|
| `LumenCore` | модели (`Page`, `Block`, `Source`, `DataTable`…) и чистая логика (порядок, Markdown, формулы, листы, распознавание фигур) | SwiftUI, GRDB, файлы |
| `LumenStorage` | SQLite через GRDB: `AppDatabase`, миграции, репозитории (расширения `AppDatabase`), запросы для экранов, поиск FTS5, копии, экспорт, синк-журнал, синк через папку | экраны |
| `LumenThemes` | токены темы, фон, карточки, анимации | данные |
| `LumenReader` | конвертеры книг в HTML, WebReader (WKWebView + JS), PDFReader (PDFKit), текстовый режим PDF, разбор полей и колонок PDF | база |
| `LumenSync` | `FolderSyncController` (синк через iCloud Drive), `CloudSync` (CloudKit, выключен; режим Swift 5) | экраны |
| `LumenUI` | все экраны SwiftUI и их `@Observable` модели | |

## 4. Главные потоки

**Запуск.** `App/LumenApp.swift`: `AppEnvironment.database()` → `AppDatabase.makeDefault()` (миграции), при ошибке экран `DatabaseRecoveryView`. Окно: `RootView(database:)` с `.lumenThemed()`; на узком экране (iPhone) `RootView` показывает `PhoneRootView`. Входящие ссылки ловит `.opensIncomingLinks`. Синк запускается при старте и при каждом возвращении в приложение (`scenePhase` → `syncNow`). Синк стартует в `AppEnvironment.startSync`.

**Открыть что-то.** Любой экран зовёт `@Environment(\.appActions)` (`Navigation/AppActions.swift`) → `Workspace.open` / `openBeside` / `openLink` (`Navigation/Workspace.swift`) → `RootView.detail` рисует `SidebarItem`. Ссылки из заметки в разделённом окне идут в соседнюю панель: `RootView.openLink(_:from:)`. Входящие файлы и `lumen://` ссылки: `Incoming/IncomingOpen.swift` (`IncomingOpenQueue`), разбор ссылки `LumenCore/LumenLink.swift`.

**Правка заметки.** `PageEditorView` → `PageEditorModel` (источник правды, пока страница открыта) → `scheduleSave` через 350 мс → `AppDatabase.savePageEdits` (`BlockRepository.swift`) → триггеры пишут `syncChange`. Undo/redo в модели (`recordUndo`, `undo`, `redo`). Тесты ждут сохранения через `model.flush()`. Живые редакторы: `Editor/OpenPageEditors.swift`. История версий: `snapshotVersion` → `PageVersionRepository.swift`.

**Экраны читают базу** через снимки из `LumenStorage/Queries.swift` (`SidebarSnapshot`, `LibrarySnapshot`, `ShelfSnapshot`, `HomeSnapshot`, `TrashSnapshot`, `PageLinksSnapshot`) и `ReadingRepository.swift` (`SourceDashboardSnapshot`, `HomeReadingSnapshot`, `ReadingOverviewSnapshot`, `ShelfReadingSnapshot`), наблюдаемые через GRDB `ValueObservation`.

**Читалка.** `ReaderModel.open` → `DocumentConverter` (`LumenReader/ReadableDocument.swift`) делает HTML для `WebReaderController`, PDF идёт в `PDFReaderController`. Место чтения `saveReadingPosition` / `setReadingLocator`, выделения `addHighlight`, время `saveReadingSession`. Заметки книги создаются лениво: `ReaderModel.ensureNotes()` → `SourceRepository.notesPage` / `bookNotesPage`.

**Синхронизация.**
- Журнал: каждая запись в синк-таблицы попадает в `syncChange` триггерами (`LumenStorage/SyncSchema.swift`: `SyncTable`, `createSyncTriggers`, `createSyncClock`, `createSyncClockTriggers`), даже когда синк выключен.
- Через папку (по умолчанию): `LumenSync/FolderSyncController.swift` (UI-сторона, закладка папки, `turnOnInICloudDrive`) → `LumenStorage/FolderSync.swift` (`FolderSyncEngine`: пишет свои файлы в `Lumen Sync/devices/<id>/`, читает чужие) → `FolderSyncRepository.swift` (`folderSyncOutgoing`, `applyFolderEntries`, побеждает поздний `syncClock.changedAt`). Совет, куда класть папку: `FolderSyncPlace.swift`.
- CloudKit (выключен): `LumenSync/CloudSync.swift` + `LumenStorage/SyncRepository.swift`.
- UI: `SyncSetupViews.swift`, `SyncStatusRow.swift`, `Backup/DataSafetyView.swift`.

## 5. База данных

Файл `lumen.sqlite` в Application Support/Lumen (`AppDatabase.defaultFolder`). Вложения (картинки, файлы книг) лежат рядом в `Attachments/`: `LumenStorage/Attachments.swift` (`AttachmentStore`).

**Таблицы:** `page`, `block`, `link` (ссылки между страницами), `pageSearch` (FTS5), `folder`, `source` (книги и файлы), `highlight`, `readingSession`, `dataTable`, `boardPin` (не используется, держится для синка), `pageVersion` (только локально), `pageTemplate`, служебные `syncChange`, `syncClock`, `syncState`, `syncRecordMetadata`, `syncIncoming`, `syncApplying`.

**Синк-таблицы** (`SyncTable`, по порядку зависимостей): `folder`, `source`, `page`, `dataTable`, `block`, `highlight`, `readingSession`, `boardPin`, `pageTemplate`.

**Миграции** в `LumenStorage/AppDatabase.swift` (`migrator.registerMigration`), только добавлять в конец:

| Миграция | Что |
|---|---|
| v1 | `page`, `block`, поиск `pageSearch` |
| v2 | обложка страницы, таблица `link` |
| v3 | фон страницы |
| v4 | `folder`, холст библиотеки (`folderId`, `canvasX/Y` у страницы) |
| v5 | `source`, `highlight` |
| v6 | `highlight.deletedAt` |
| v7 | `readingSession` |
| sync: change log | журнал `syncChange` |
| v8 | `dataTable`, `page.databaseId` / `properties` |
| book notes beside books | заметки книги в папку книги |
| v9 | `block.drawing`, `page.kind` (тетради) |
| v10 | `folder.icon` |
| v11 | `source.shelfOrder` |
| sync: folder clock, reading sessions | `syncClock`, синк времени чтения |
| v12 | `folder.isShelf` |
| v13 | `source.customCover`, `spineCenter` |
| v14 | `page.shelfPin` |
| v15 | `boardPin` |
| v16 | индексы для скорости |
| v17 | `readingSession.startProgress` / `endProgress` |
| v18 | `pageVersion` |
| v19 | `pageTemplate` |
| v20 | `page.coverCrop` |

**Репозитории** (все это `extension AppDatabase` в `LumenStorage/`):

| Файл | Главные функции |
|---|---|
| `PageRepository.swift` | `createPage`, `createQuickNote`, `createNotebook`, `updatePage`, `renamePage`, `movePage`, `duplicatePage`, `trashPage`, `restorePage`, `emptyTrash`, `setCover`, `setCoverCrop`, `setBackground`, `setIcon`, `setFavorite`, `setShelfPin` |
| `BlockRepository.swift` | `blocks`, `saveBlock`, `savePageEdits` (пакетное сохранение редактора), `deleteBlock`, `updateLinks` |
| `FolderRepository.swift` | `createFolder`, `createShelf`, `setFolderShelf`, `moveFolder`, `renameFolder`, `trashFolder`, `setFolderColor`, `setFolderIcon`, `setPosition(s)`, `returnToInbox` |
| `SourceRepository.swift` | `addSource`, `updateSource`, `trashSource(s)`, `arrangeShelf`, `placeOnShelf`, `moveSource`, `addHighlight`, `updateHighlight`, `setHighlightNote`, `setHighlightColor`, `deleteHighlight`, `saveReadingPosition`, `setReadingLocator`, `notesPage`, `bookNotesPage`, `setCustomCover`, `setSpineCenter` |
| `DataTableRepository.swift` | `createDataTable`, `updateDataTable`, `addProperty`, `addRow`, `insertRow`, `setValue`, `moveRow`, `addRelation`, `setRelationTwoWay`, `syncPairedRelation`, `tasksDataTable`; снимки `DataTableSnapshot`, `DataRowSnapshot` |
| `ReadingRepository.swift` | `saveReadingSession`, `readingStats`; снимки дашборда, Стола, «Чтения», полки |
| `TrashRepository.swift` | `deleteForever`, `purgeTrash` (`trashRetentionDays` = 30) |
| `Search.swift` | `search` (FTS5), `searchEverything` (⌘K: страницы по тексту, книги по названию и автору, выделения) |
| `Backup.swift` | `writeBackup`, `restoreBackup`, автокопии `AutomaticBackup`, `recoverDefault` |
| `Export.swift` | `exportMarkdown`, `pageExport` |
| `PageVersionRepository.swift` | `savePageVersion`, `pageVersions` |
| `PageTemplateRepository.swift` | `pageTemplates`, `savePageTemplate`, `deletePageTemplate` |
| `BookDuplicatesRepository.swift` | `mergeDuplicateBooks` |
| `BoardRepository.swift` | `removeOrphanBoardPins` |
| `SyncRepository.swift` / `FolderSyncRepository.swift` | см. §4 |

## 6. Файлы по модулям

### 6.1 LumenCore (модели и логика)

| Файл | Что |
|---|---|
| `Page.swift` | `Page` (дерево `parentId`, `inInbox`, `pageKind`, `sourceId`, `databaseId` + `properties`, `shelfPin`), `CoverCrop`, `PageCover`, `PageBackground`, `Wallpaper` |
| `Block.swift` | `Block` (дерево `parentBlockId`), `BlockContent` (JSON), `BlockColor`, `TextRun`, `TextMark` |
| `BlockType.swift` | все типы блоков, их названия и значки |
| `BlockSelection.swift` | выделение нескольких блоков, `BlockClipboard`, `ImageSizing` |
| `BlockComment.swift` | комментарии к блоку (в `BlockContent.comments`) |
| `SyncedBlock.swift` | синхронные блоки: `SyncedReference` |
| `TableData.swift` | простая таблица в заметке |
| `Attachment.swift` | `FileAttachment`, `WebBookmark`, `WebPreview` |
| `YouTubeLink.swift` | разбор ссылок YouTube |
| `InlineMarkup.swift` | разметка внутри блока ↔ `TextRun` |
| `MarkdownPaste.swift`, `MarkdownShortcut.swift` | вставка Markdown блоками; `# `, `- ` и т.п. при наборе |
| `MentionTrigger.swift` | `[[` и `@` |
| `CodeSyntax.swift` | подсветка кода: `CodeLanguage`, `CodeHighlighter` |
| `NoteSheets.swift` | листы A4 заметки: `paginate`, `overflowIndex` |
| `PageContents.swift` | строки блока «Оглавление» |
| `PageExport.swift` | страница → Markdown / структура для PDF |
| `PageTemplate.swift`, `PageVersionPolicy.swift` | шаблоны страниц; когда сохранять и прореживать версии |
| `Folder.swift` | `Folder` (`isShelf`, `icon`, цвет), `LibraryLayout`, `LibraryItemID` |
| `Source.swift` | `Source`, `SourceFormat`, `SourceLocator`, `Highlight`, `HighlightColor`, `ExcerptReference` |
| `LumenLink.swift` | `lumen://page/…`, `source/…`, `…/highlight/…`, `…/place?…` |
| `ReadingStats.swift`, `ReadingInsights.swift` | `ReadingSession`, `ReadingStats`, `ReadingForecast`, `ReadingOverview` |
| `ShelfSort.swift`, `ShelfDisplay.swift` | `ShelfSort`, `ShelfGroup`, `ShelfNote`, `ShelfStatus`; `ShelfDisplay`, `ShelfSearch` |
| `BookDuplicates.swift` | поиск дублей книг |
| `DataTable.swift` | базы: `DataTable`, `PropertyType`, `PropertyDefinition`, `PropertyValue`, `DataView`, `DataFilter`, `DataSort`, `DataQuery` (фильтры и сортировки в памяти), `DataTableTemplate` |
| `Formula.swift`, `DataRelation.swift` | формулы; связи и сводки (`RelationConfig`, `RollupConfig`, `Rollup`) |
| `Notebook.swift`, `NotebookItem.swift`, `NotebookSheets.swift`, `NotebookSheetEdits.swift` | `PageKind`, `PaperPattern`, `PaperTone`, `NotebookLayout`; картинки и текст на листе; фон листа; перестановка листов и поиск по почерку |
| `ShapeRecognizer.swift` | ровные фигуры из штриха |
| `PaneArrangement.swift` | две панели: рядом / друг под другом / поменять |
| `SortKey.swift` | дробные ключи порядка (base62) |
| `BoardPin.swift` | старая доска связей, не используется |
| `RelativeDate.swift` | «вчера», «3 дня назад» |

### 6.2 LumenStorage

`AppDatabase.swift` (открытие, миграции), `Queries.swift` (снимки для экранов, см. §4), `SyncSchema.swift` (синк-таблицы и триггеры), `Attachments.swift`, `Search.swift`, `Backup.swift`, `Export.swift`, `FolderSync*.swift`, репозитории из §5.

### 6.3 LumenReader

| Файл | Что |
|---|---|
| `ReadableDocument.swift` | `DocumentConverter` (выбор конвертера по формату), `ReadableDocument`, `TocEntry`, `PreparedDocument` |
| `EPUBConverter`, `FB2Converter`, `DOCXConverter`, `PPTXConverter`, `TextConverter` (+ `CBZConverter`) | форматы → HTML |
| `XMLTree.swift` | мелкий XML-разбор для конвертеров |
| `SourceMetadata.swift` | название, автор, обложка при добавлении |
| `WebReader.swift` | `WebReaderController`, `WebReaderView` (WKWebView) |
| `ReaderScript.swift` | JS внутри книги; `ReaderAppearance` (шрифт, размер, палитра) |
| `ReadingScale.swift` | процент прочитанного по объёму текста |
| `PDFReader.swift` | `PDFReaderController`, `PDFReaderView`, выделения и события PDF |
| `PDFPageTint.swift` | перекраска страниц PDF под тему |
| `PDFPageLayout.swift` | поля и колонки: `PDFLayoutAnalyzer` (кэш в Caches/LumenReader/pdf-layout), `PDFLayoutPlan` |
| `PDFTextConverter.swift`, `PDFTextLayout.swift` | режим «Текст» для PDF: `PDFTextIndex`, `PDFTextFinder` |
| `QuickLookView.swift` | остальные файлы через системный просмотр |
| `SpeechText.swift` | чтение вслух: куски главы из `ReaderScript.speechBlocks` → части-предложения (`SpeechPart`) с местом в символах главы (UTF-16, как `textOffset`); код → «пример кода пропущен», сноски и номера страниц выкидываются |
| `SpeechVoice.swift` | голоса Apple (`SpeechVoices`), `SpeechVoicePlayer` поверх `AVSpeechSynthesizer` (очередь на 2 части вперёд, скорость 0.5–3×); протокол `SpeechPlaying` для обоих голосов |
| `NeuralVoice.swift` | ElevenLabs по ключу пользователя: `ElevenLabsClient` (аккаунт, голоса, звук фразы mp3), `NeuralVoiceError`, `NeuralVoiceModel` (v3 takes no neighbour sentences, v2 no language code), `NeuralVoiceTuning` (stability / style → `voice_settings`, part of the cache key), кеш озвученного `NeuralVoiceCache` (Caches/LumenReader/voice; `NeuralVoiceFetches` скачивает каждую фразу один раз и доводит загрузку до кеша, даже если плеер её отменил: знаки уже списаны), ключ в Связке ключей `NeuralVoiceKey` |
| `NeuralVoicePlayer.swift` | `NeuralVoicePlayer`: фразы через `AVAudioPlayer`, 2 следующие скачиваются по очереди, при ошибке `onFailure` (читалка переходит на Apple); `NeuralVoiceSample` для «Послушать» |

### 6.4 LumenThemes

`Theme.swift` (токены, `AppearanceMode`, `\.lumenTheme`), `Components.swift` (`ThemedBackground`, `lumenCard`, `lumenGlass`, `StatCard`), `LayeredWallpaper.swift` (обои фона страницы), `Motion.swift` (`LumenMotion`), `ThemeContrast.swift` (цвета папок не теряются на фоне), `CoverTinting.swift` (`Theme.tinted(by:)`).

### 6.5 LumenUI: корень, навигация, общее

| Файл | Что |
|---|---|
| `RootView.swift` | `SidebarItem`, корневой экран Mac/iPad, `detail`, `openLink`, `tabShortcuts`, `paletteExtras` |
| `Phone/PhoneRootView.swift` | весь iPhone: `PhoneRoute`, `PhoneTab`, капсула `PhoneTabCapsule` |
| `Navigation/AppActions.swift` | `appActions`, «Создать», `CaptureField`, `SettingsSheet` |
| `Navigation/Island.swift`, `BubbleBar.swift` | остров и кружок с вырезом |
| `Navigation/IslandTabs.swift` | вкладки кружками слева от острова, список «+N», меню вкладки |
| `Navigation/Workspace.swift`, `WorkspaceViews.swift` | вкладки, история, перетаскивание вкладок, `ItemTitle`, `PaneHeader` |
| `Navigation/PaneSplit.swift`, `PaneLayout.swift` | две панели (`PaneSplit`, `TwoPaneLayout`, `PaneArrangementControls`) |
| `Navigation/CommandPalette.swift` | ⌘K |
| `Navigation/KeyHints.swift` | ⌘J |
| `Navigation/FocusMode.swift` | режим фокуса, лампа, таймер |
| `Navigation/ScreenOptions.swift` | что видно на экране (вкладки, «Сохранено», прогресс читалки) |
| `Navigation/ThemeSettings.swift` | `.lumenThemed()`, `LumenThemeHost`, `WindowAppearance`, `AppearanceSection`, `AppIcon` |
| `Navigation/Setting.swift` | `@Setting` вместо `@AppStorage` |
| `Navigation/GeometryBox.swift` | размеры для обработчиков без перерисовки |
| `Navigation/IconPicker.swift` | выбор эмодзи-значка |
| `Navigation/OutsideClick.swift` | закрыть лист щелчком мимо (Mac) |
| `Navigation/WindowChrome.swift` | заголовок окна Mac в цвет темы |
| `HomeView.swift` | «Стол» |
| `InboxView.swift` | «Записки», разбор, Архив |
| `SearchView.swift` | поиск на iPhone (вкладка «Поиск»); на Mac/iPad ⌘K это `CommandPalette` |
| `SyncSetupViews.swift`, `SyncStatusRow.swift` | включение синка, статус |
| `Notices.swift` | всплывашки, `lumenLog` |
| `LumenSounds.swift` | звуки |
| `Incoming/IncomingOpen.swift`, `CopyLink.swift` | открытие файлов и ссылок извне, «Скопировать ссылку» |
| `Backup/DataSafetyView.swift`, `DatabaseRecoveryView.swift` | «Данные и копии», экран спасения базы |
| `Export/PageExportModifier.swift`, `PagePDFRenderer.swift` | кнопки экспорта, рисование PDF |
| `Preview.swift` | база для превью SwiftUI |

### 6.6 LumenUI/Editor (редактор заметок)

| Файл | Что |
|---|---|
| `PageEditorModel.swift` | модель страницы: загрузка, сохранение (`scheduleSave`, `flush`), undo/redo, подстраницы, обложка, версии |
| `+Blocks` | добавить / удалить / сменить тип блока, текст, галочки, цвет |
| `+Structure` | вложенность (Tab / ⇧Tab), колонки, перенос блока |
| `+Selection` | выделение нескольких блоков |
| `+Format` | форматирование выделенного текста, ссылки |
| `+Paste` | вставка Markdown и блоков |
| `+Media` | выписки из книг, ссылки на место в книге, картинки, обложка и фон |
| `+Attachments` | файлы, PDF, видео, аудио, закладки сайтов (`WebPreviewLoader`) |
| `+Table`, `+Comments`, `+Synced`, `+Templates` | таблица, комментарии, синхронные блоки, шаблоны |
| `+Sheets` | листы A4 |
| `+Drawing` | рисунки и тетради внутри страницы |
| `PageEditorView.swift` | экран редактора, `SheetStack`, `LiveSheetRail`, `LiveOutline`, `EditorCommands` (меню Mac) |
| `BlockRow.swift` | строка блока: поле, ручка, меню, перетаскивание (`BlockDropDelegate`), `SlashMenu`, `PageLinkMenu`, выписка-вырезка, `RowHover` |
| `BlockTree.swift` | вложенные блоки и колонки |
| `BlockSelectionViews.swift`, `BlockPasteboard.swift` | рамка выделения, панель действий; буфер обмена |
| `FormatBar.swift` | плавающая панель формата, «Формат» в системном меню, `FormatBarClickCatcher` |
| `CodeBlockBody.swift` | блок кода и подсветка при наборе |
| `MathViews.swift` | формулы TeX (SwiftMath) |
| `ImageBlock.swift`, `AttachmentImage.swift`, `AttachmentBlocks.swift`, `YouTubeEmbed.swift` | картинки, файлы, видео, аудио, закладки, YouTube |
| `TableBlock.swift`, `DatabaseBlock.swift`, `TableOfContentsBlock.swift`, `SyncedBlockViews.swift` | таблица, база внутри заметки, оглавление, синхронный блок |
| `BlockComments.swift`, `BlockColors.swift` | комментарии, цвета блока |
| `NoteSheetViews.swift`, `SheetLoading.swift` | листы A4 (`SheetPaper`, `AddSheetBar`, `SheetRail`, `SheetPager`), отложенная отрисовка (`SheetLoader`, `DeferredSheet`) |
| `PageCoverBand.swift`, `CoverTint.swift`, `PageBackgroundPicker.swift` | обложка с «Ракурсом», цвет окна по обложке, фон страницы |
| `PageChrome.swift` | хлебные крошки, «Сохранено», счётчик слов, типы блоков на iPhone |
| `PageOutlineView.swift`, `SubpagesPanel.swift`, `PageLinkPreview.swift` | карта заголовков справа, подстраницы, превью ссылки |
| `PageHistorySheet.swift`, `TemplateSuggestions.swift` | история версий, шаблоны на пустой странице |
| `OpenPageEditors.swift` | реестр открытых редакторов и читалок |
| `EmptyBackspace.swift` | Backspace в пустом блоке на iPhone |

### 6.7 LumenUI/Reader (читалка)

| Файл | Что |
|---|---|
| `ReaderModel.swift` | открытие, переходы (`go`, `turnPage`, главы), выделения, выписки, масштаб PDF, заметки рядом, время чтения |
| `ReaderView.swift`, `+Book`, `+Notes` | экран книги и панель заметок рядом / снизу |
| `ReaderChrome.swift` | мягкий стиль, прогресс, панель вида (`ReaderAppearancePanel`) |
| `ReaderSelectionBars.swift`, `HighlightNote.swift` | панель у выделения, заметка к выделению |
| `ReaderSidePanels.swift` | оглавление и список выделений |
| `SidePagePicker.swift`, `ReaderLayoutStore.swift` | какая страница рядом с книгой, где панель заметок |
| `ExcerptDrag.swift` | перетащить выписку в заметку |
| `ReaderKeys.swift` | стрелки на Mac |
| `ReadAloud.swift` | чтение вслух на всё приложение (`ReadAloud.shared`): держит `ReaderModel` звучащей книги, подсветка через `WebReaderController.markSpoken`, место чтения за голосом (`ReaderModel.listened`), следующая глава, таймер сна, экран блокировки (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`); открыли книгу снова → `adopt` |
| `ReadAloudViews.swift` | `ReadAloudBar` (остров-плеер в читалке, `RootView.showsPlayerIsland`), `ReadAloudRing` (кружок у острова), `ReadAloudPanel` (голос, скорость, таймер), `PhoneMiniPlayer`, `PhoneFullPlayer`, `ReadAloudSettingsSection` |
| `NeuralVoiceSettings.swift` | Настройки → «Нейроголос по своему ключу»: ключ, проверка, голос, модель, «Послушать», кеш |
| `SourceImporter.swift` | добавление книг из файлов |
| `SourceDashboardView.swift`, `ReadingOverviewView.swift`, `ReadingWidgets.swift` | дашборд книги, экран «Чтение», цель, тепловая карта |

### 6.8 LumenUI/Library (полка и библиотека)

| Файл | Что |
|---|---|
| `LibraryView.swift` + `+Actions`, `+Tiles`, `+SystemMenu` | холст «Полки», действия, плитки, системное меню плиток по долгому нажатию (iPhone, iPad) |
| `LibraryTiles.swift`, `LibraryComponents.swift`, `ItemLabels.swift` | плитки папок, страниц, книг, тетрадей |
| `LibraryCompactList.swift` | список на iPhone |
| `MoveToFolderSheet.swift`, `GlassMenu.swift` | «Переместить в папку», стеклянное меню |
| `BookShelf.swift` | полка с корешками, перетаскивание, сортировка, фильтр статуса |
| `ShelfViews.swift` | поиск, «Корешки / Обложки / Список», плитка «Перетащите сюда файл» |
| `ShelfSheets.swift` | заметки на полке |
| `ShelfReadingNow.swift`, `BookShowcase.swift`, `BookStatsCard.swift` | «Читаю сейчас», витрина книги |
| `BookCover.swift` | своя обложка |
| `StudyLamp.swift` | лампа на полке Стола |

### 6.9 LumenUI/Drawing (рукопись)

| Файл | Что |
|---|---|
| `NotebookView.swift` | экран тетради |
| `PencilCanvas.swift` | PencilKit (iPad / iPhone) |
| `MouseDrawing.swift` | рисование мышью на Mac (`MouseInk`, `MouseDrawingLayer`) |
| `NotebookItemsViews.swift` | инструменты, картинки и текст на листе |
| `NotebookSheetStrip.swift` | миниатюры листов, переход, перестановка |
| `DrawingLasso.swift`, `ShapeSnapping.swift` | лассо, ровные фигуры |
| `DrawingSupport.swift` | шаблоны бумаги (`PaperGeometry`), кэш картинок |
| `SheetPDFImages.swift` | PDF и страницы книг как листы |
| `HandwritingReader.swift` | распознавание почерка (Vision) для поиска |
| `NotebookPasteboard.swift`, `DrawingColors.swift`, `DrawingBlock.swift` | буфер, цвета, рисунок внутри заметки |

### 6.10 LumenUI/Database (базы и задачи)

| Файл | Что |
|---|---|
| `DataTableScreen.swift` | экран базы, `DataTableBody` (и внутри заметки), меню свойств, `RowPropertiesPanel`, `PageScreen` (страница по ссылке: открывает редактор или базу, им пользуется `RootView.detail` для `.page`), `TasksScreen` («Дела») |
| `DataTableModel.swift` | модель базы |
| `DataLayouts.swift` | таблица, список, доска, календарь |
| `PropertyViews.swift` | показ и правка значений |
| `RelationViews.swift`, `FormulaEditor.swift` | связи и сводки, формулы |

## 7. Тесты

| Где | Что |
|---|---|
| `Packages/LumenKit/Tests/LumenCoreTests/` | чистая логика (Markdown, формулы, листы, фигуры, сортировки) |
| `Tests/LumenStorageTests/` | репозитории, миграции, синк через папку, копии; база `AppDatabase.inMemory()` |
| `Tests/LumenReaderTests/` | конвертеры, PDF-разметка, текстовый режим |
| `Tests/LumenUITests/` | модели экранов (`PageEditorModel`, полки, вкладки), не XCUITest |
| `UITests/` | XCUITest на macOS: набор, клавиши, перетаскивание блоков, панель формата, навигация, открытие файлов. Только в CI |

Тест к файлу обычно называется так же: `PageTemplate.swift` → `PageTemplateTests.swift`, модель → `…ModelTests.swift`.

## 8. Документы

| Файл | Что |
|---|---|
| `.claude/CLAUDE.md` (= `AGENTS.md`) | правила владельца и подводные камни |
| `docs/FEATURES.md` | что уже есть в приложении |
| `docs/CODE_MAP.md` | этот файл |
| `docs/ROADMAP.md` | план по шагам |
| `docs/PRODUCT_SCOPE.md` | направление продукта |
| `docs/design/` | значок приложения, картинки-образцы |
| `README.md` | описание для GitHub, список функций (англ.) |
