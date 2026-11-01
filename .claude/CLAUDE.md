# Lumen: notes for coding agents

Read this first. It tells you where things live and which rules the owner set, so you don't have to re-read the whole codebase.

Lumen is a native notes app for Mac, iPhone and iPad (Swift 6, SwiftUI, iOS 18+ / macOS 15+): Notion-like block pages, a reader for almost any book format with excerpts that link back to the exact place, Goodnotes-like handwriting, task databases, and a dark "Sunset" look. The plan, in Russian, is `docs/ROADMAP.md` (one GitHub issue per step, done in order). The app UI is in Russian.

## Working rules (from the owner)

- **Talk to the owner in Russian, simply.** They are new to git and PRs: say what changed for them in the app, not in git terms, and give exact steps when they have to do something.
- **Nothing goes to `main` without the owner.** Work on your own branch, open a PR, let the owner merge it.
- **Commits and PRs carry no AI attribution** (the repo is public). Commit as the owner:
  ```sh
  git -c user.name=BradD06 -c user.email=173235502+BradD06@users.noreply.github.com commit -m "..."
  ```
  No `Co-Authored-By:` or session trailer lines, no "Generated with ..." footer or session links in PR descriptions. Never use the owner's personal email.
- When you open a PR, assign it to `BradD06`. Don't request their review: they are the PR author, so it fails.
- **The owner runs the app from `~/Desktop/Lumen` on their Mac** (`~/Developer/Lumen` is an old, empty location). If you can reach that Mac, put your changes there first so they see them in Xcode right away, then commit and push. Before touching it, run `git status -sb` there: the folder sometimes stays on an old feature branch. After a PR is merged, switch it back to `main` and pull.
- Don't run the macOS UI tests on the owner's Mac: they take over the mouse. CI runs them.
- When a PR adds something users can see, update the Features list in `README.md` (English).
- No flashcards or spaced repetition: the owner rejected them.

## Build and test

- `make open`: runs `xcodegen generate` and opens `Lumen.xcodeproj`. The Xcode project and `App/Info.plist` are generated from `project.yml` and are not in git, so edit `project.yml`, never the project file.
- `make test` = `swift test --package-path Packages/LumenKit` (Swift Testing, `@Test` / `#expect`).
- Signing: `Config/Signing.xcconfig` includes the gitignored `Config/Local.xcconfig`, which holds the owner's `DEVELOPMENT_TEAM`. Bundle id is `io.github.bradd06.lumen`.
- CI (`.github/workflows/ci.yml`, macOS 15 runners) runs on every PR: package tests, app build for iOS Simulator and macOS, and macOS UI tests (`UITests/`, target `LumenAppUITests`). The app launched with `-uiTesting` uses an in-memory database and saves no workspace state.
- **A Linux cloud container has no Swift toolchain**, and swift.org downloads are blocked there. Then CI on the PR is the only compile and test check: push, then read the job logs.
- On the Mac, `swift test` inside `~/Desktop` fails to codesign `GRDB_GRDB.bundle` (Desktop extended attributes). Use `swift test --package-path Packages/LumenKit --scratch-path /tmp/lumen-build`.

## Layout

```
App/                     @main LumenApp, macOS app delegate (open files / lumen:// links), QuickNoteIntent (Shortcuts, Siri)
Config/                  Signing.xcconfig, iCloud entitlements (used only when sync is turned on)
Packages/LumenKit/       one local SwiftPM package, all app code lives here
  Sources/LumenCore/     models and pure logic, no dependencies
  Sources/LumenStorage/  SQLite via GRDB 7: AppDatabase, migrations, repositories, queries, FTS5 search, backup, sync log
  Sources/LumenThemes/   Theme tokens, Sunset theme, LayeredWallpaper, glass/vivid card components
  Sources/LumenReader/   format converters to HTML, WebReader (WKWebView + ReaderScript JS), PDFReader (PDFKit), QuickLook
  Sources/LumenSync/     CloudSync over CKSyncEngine (Swift 5 language mode; off by default)
  Sources/LumenUI/       all SwiftUI screens and their @Observable models
  Tests/                 LumenCoreTests, LumenStorageTests, LumenReaderTests, LumenUITests (model-level, not XCUITest)
UITests/                 XCUITest on macOS (typing, keyboard, block drag, navigation, opening files)
docs/                    ROADMAP.md, design/ (app icon SVGs, reference images)
```

Dependencies only go downward: `LumenUI` → `LumenReader`, `LumenSync`, `LumenStorage`, `LumenThemes` → `LumenCore`. New modules become new targets in `Packages/LumenKit/Package.swift`.

## Where features live

**Data model (LumenCore).** `Page` (tree via `parentId`, `inInbox` flag, `pageKind` for notebooks, `sourceId` for book notes, `databaseId` + `properties` for database rows), `Block` (tree via `parentBlockId`, `BlockType`, JSON `content`), `Folder` (library canvas positions, `LibraryLayout`), `Source` (a book or file) with `SourceLocator`, `Highlight`, `ExcerptReference`, `DataTable` (database properties and views as JSON, `DataQuery` filters and sorts in memory), `Notebook` / `NotebookItem` / `NotebookSheets`, `LumenLink` (`lumen://page/<id>`, `source/<id>`, `source/<id>/highlight/<id>`, `source/<id>/place?...`), `SortKey` (base62 fractional order keys, used for every ordered list).

**Storage (LumenStorage).** `AppDatabase` (`makeDefault()`, `inMemory()` for tests, migrations in `AppDatabase.swift`), one repository file per area (`PageRepository`, `BlockRepository`, `FolderRepository`, `SourceRepository`, `DataTableRepository`, `ReadingRepository`, `TrashRepository`), read models in `Queries.swift` (`SidebarSnapshot`, `LibrarySnapshot`, `InboxQuery`, `HomeSnapshot`, `TrashSnapshot`, `PageLinksSnapshot`) that screens watch with GRDB `ValueObservation`. `Search.swift` is FTS5. `Attachments.swift` is `AttachmentStore` (images, book files). `Backup.swift` is zip backup and restore; `Export.swift` exports pages.

**Screens (LumenUI).**
- Root and navigation: `RootView.swift` (`SidebarItem` enum, `detail(_:pane:)` renders each pane), `SidebarView`, `Navigation/Workspace.swift` (tabs, per-pane back/forward history, split panes, saved in UserDefaults `workspace.v1`), `Navigation/WorkspaceViews.swift` (`ItemTitle`, tab bar, drag-a-tab-to-split). iPhone uses `Phone/PhoneRootView.swift` (4 tabs) instead.
- Editor: `Editor/PageEditorModel.swift` plus `+Blocks`, `+Structure`, `+Media`, `+Drawing` extensions (the model is the source of truth while a page is open, saves in batches after 350 ms, owns undo/redo), `PageEditorView`, `BlockRow`, `BlockTree`, `BlockColors`, `CodeBlockBody`, `EmptyBackspace` (iPhone backspace in an empty block), `OpenPageEditors` (registry of live editors).
- Library: `Library/LibraryView*.swift` (canvas of pages, notebooks, books and folders), `LibraryTiles`, `LibraryCompactList` (iPhone), `MoveToFolderSheet`, `GlassMenu`.
- Reader: `Reader/ReaderModel.swift` (opening, position, highlights, excerpts, reading time, notes beside the book), `ReaderView` + `+Book` / `+Notes`, `ReaderChrome` (soft style, progress, appearance panel), `SidePagePicker` (any page in the side pane), `SourceDashboardView` (per-book dashboard), `SourceImporter`.
- Handwriting: `Drawing/` (`PencilCanvas` on iOS, `MouseDrawing` on macOS since there is no PKCanvasView there, `DrawingLasso`, `NotebookView`, `NotebookItemsViews`, `SheetPDFImages` for PDF pages as sheets, `NotebookPasteboard`).
- Databases and tasks: `Database/` (`DataTableModel`, `DataTableScreen`, `DataLayouts` for table / board / calendar / list, `PropertyViews`). The task tracker is the database template `"tasks"` opened by `SidebarItem.tasks`.
- Other: `HomeView` (widget-card dashboard), `InboxView`, `SearchView`, `Backup/` (data and backups sheet, database recovery screen), `Export/` (Markdown and PDF export, `PagePDFRenderer`), `Incoming/` (`IncomingOpenQueue`, `.opensIncomingLinks`, copy link), `Notices` (`NoticeCenter` toasts, `lumenLog`), `LumenSounds`, `SyncStatusRow`.

## Conventions and gotchas

- Code comments, UI strings and most commit messages are in Russian. Keep comments short and about why. Commit messages: one short line on what changed for the user.
- **Migrations are append-only and named** (`"v9: drawings, notebooks"`). Never edit a shipped migration, add a new one at the end. When two branches both add one, keep both and pick a sensible order.
- **A new synced table** needs a `SyncTable` case (in dependency order) and `createSyncTriggers(db, table:)` in its migration. Every change to synced tables is logged to `syncChange` even while sync is off.
- **iCloud sync stays off** in the default build: never add iCloud entitlements or a container to `project.yml`. It turns on only through `Config/Local.xcconfig` (see README). The long-term plan is Supabase sync instead.
- A new `SidebarItem` case needs a title in `ItemTitle` and a branch in `RootView.detail`, and on iPhone in `PhoneRootView`.
- In split screen, toolbars and shortcuts of the inactive pane are hidden via the `isActivePane` environment value. Never switch a view's identity on `isActivePane` (an `if/else` on it rebuilds the whole editor on focus change).
- Links clicked in a note open in the opposite pane when the tab is split (`RootView.openLink(_:from:)`). Excerpts from a book go to the note open beside it (`besidePageId`), otherwise to the book's notes. Book notes live in the book's folder next to the book and are created lazily (`ReaderModel.ensureNotes()`).
- Custom drag types and document types are declared in `project.yml` under `info:`. Don't set `LSSupportsOpeningDocumentsInPlace` (Xcode rejects `NO` for the macOS side).
- In `LumenUI` files that import GRDB, write `ButtonStyleConfiguration`, not `Configuration` (name clash).
- Tests: use `AppDatabase.inMemory()`. Wait for the editor to save with `model.flush()`, not sleeps. Keep heavy PDF / Core Image rendering out of main-actor tests, it slows the timing-sensitive ones on CI.
- `UserDefaults` keys in use include `workspace.v1`, `reader.*` (appearance, `reader.sidePage.<sourceId>`, `reader.pdfZoom.<sourceId>`) and `drawing.recentColors`.
