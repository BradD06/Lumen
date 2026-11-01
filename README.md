<p align="center">
  <img src="docs/design/app-icon/lumen-icon-ios.svg" width="128" height="128" alt="Lumen app icon">
</p>

<h1 align="center">Lumen</h1>

<p align="center">
  <b>Notes, books and tasks in one calm place.</b><br>
  A native notes app for studying, reading and planning, made for Mac, iPhone and iPad.
</p>

<p align="center">
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20iPadOS-f08a5d">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-fa7343?logo=swift&logoColor=white">
  <img alt="Status" src="https://img.shields.io/badge/status-in%20development-8a6fd1">
</p>

---

Lumen takes the flexible block pages of Notion and puts your reading next to them. Open a book or any document, read it in the app, and write notes beside it. Every quote you save remembers the exact spot in the book it came from, so one tap takes you back there. Write by hand like in a paper notebook, track your tasks in databases, and keep everything in a warm, dark "Sunset" look.

## Features

### ✍️ Block notes
- A block editor with paragraphs, headings, lists, to-dos, quotes, callouts, code blocks with syntax highlighting, dividers, images and toggles.
- Markdown shortcuts (`#`, `-`, `1.`, `[]`, `>`, ```` ``` ````, `---`) and a `/` command menu.
- Nested blocks with Tab / ⇧Tab, drag-and-drop reordering, and columns: drop a block next to another one to place them side by side.
- Text and background colors, duplicate (⌘D), full undo and redo (⌘Z / ⇧⌘Z).
- Subpages and links to any page with `[[` or `@`, plus backlinks at the bottom of every page.
- Page covers from the theme's gradients or your own photos.
- Quick note with ⌘N, from Shortcuts or from Siri. It lands in the Inbox to sort later.
- Full-text search across all pages with ⌘K.

### 📚 Reader for almost any file
- Read **EPUB, PDF, FB2, CBZ, Word, PowerPoint, RTF, ODT, Markdown, HTML and plain text** right inside the app. Other files open with Quick Look.
- Open books from Files, Telegram, Mail or Finder with "Share" / "Open with" → Lumen, or drop a file onto the Dock icon.
- Highlights with comments. Save a quote as an excerpt, and it links back to the exact place in the book.
- Bookmark a place while you write notes, and jump back to it later.
- Notes open beside the book in a split view. On iPhone they slide up as a sheet.
- Lumen remembers exactly where you stopped reading. Dark mode tints PDF pages too.
- A dashboard for every book with reading time and progress.
- `lumen://` links to a page, a book, a quote or a place in a book. Paste one into any app, and tapping it opens Lumen right there.

### 🖊️ Handwriting
- Goodnotes-style notebooks: paper sheets, pens, a 72-color palette, text boxes and images.
- Turn PDF pages, or pages of a book from your library, into notebook sheets and write over them.
- A lasso to select, move, resize and recolor strokes.
- A drawing block that fits inside any regular note.
- Apple Pencil on iPad. On the Mac you can draw with the mouse or trackpad.

### ✅ Tasks and databases
- Notion-like databases with table, board, calendar and list views.
- Typed properties, filters and sorting.
- A ready-made task tracker with Today, Board, All tasks and Calendar views.

### 🗂️ Library and workspace
- A visual library for pages, notebooks, books and folders. Notes made from a book stay right next to it.
- Browser-style back and forward, tabs (⌘T, ⌘1…9) and split screen on Mac and iPad. Drag a tab to one side of the window to open it next to another one.
- Favorites, an Inbox for quick notes, and a trash you can restore from.
- Export a page to Markdown or PDF, plus full backups of your data.
- On iPhone: Home, Inbox, Library and Search tabs at the bottom of the screen.

### 🌅 Design
- A dark "Sunset" theme with warm gradients.
- A home screen dashboard made of widget cards.

## Roadmap

Coming next, in order: reminders for tasks, more themes and page styles, built-in widgets for the home screen, sync across devices with Supabase (including a future Windows app), Sign in with Apple, and a store for widgets and themes. The full plan, in Russian, is in [docs/ROADMAP.md](docs/ROADMAP.md), with one issue per step.

## Getting started

You need **Xcode 16 or later** and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
make open        # generates Lumen.xcodeproj and opens it
```

In Xcode, choose the **Lumen** scheme and a device (iPhone, iPad or My Mac). Note that the app's interface is in Russian for now.

So you don't have to pick a development team after every `make open`, create `Config/Local.xcconfig` with the line `DEVELOPMENT_TEAM = <your team ID>`. You can find the ID in Xcode under Signing & Capabilities, or on developer.apple.com. This file is not tracked by git.

Run the tests for all modules:

```sh
make test        # same as: swift test --package-path Packages/LumenKit
```

`Lumen.xcodeproj` is not stored in git. It is generated from [`project.yml`](project.yml), so there are never merge conflicts in the project file.

## Project structure

```
App/                    app entry point (one target for iOS and macOS)
Packages/LumenKit/
  Sources/
    LumenCore/          models: pages, blocks, databases, notebooks, sources, links
    LumenStorage/       SQLite via GRDB: schema, migrations, repositories, FTS5 search, backups
    LumenThemes/        design tokens, the Sunset theme, backgrounds, widget cards
    LumenReader/        reader: EPUB, FB2, PDF, Word, PowerPoint and text converters
    LumenSync/          iCloud sync with CKSyncEngine (off for now, see below)
    LumenUI/            screens: home, inbox, sidebar, library, editor, reader,
                        handwriting, databases, search; Phone/ holds the iPhone tabs
  Tests/                tests written with Swift Testing
UITests/                macOS UI tests (XCUITest)
project.yml             Xcode project definition for XcodeGen
.github/workflows/      CI: package tests, iOS and macOS builds, UI tests
```

## Sync

Your data stays on your device. iCloud sync between iPhone, iPad and Mac is already written, but it is turned off, because iCloud needs a paid Apple Developer Program account. The plan is to move sync to Supabase, which will also work with the future Windows app.

<details>
<summary>How the iCloud sync works and how to turn it on</summary>

Every change in the database (a page, block, folder, book or highlight) is added to a `syncChange` queue by SQLite triggers, even while sync is off. The `LumenSync` module hands this queue to `CKSyncEngine` and writes records from other devices back into the database. Data lives in the user's private CloudKit database, and book files travel as assets. Search indexes and backlinks are not stored in iCloud; each device rebuilds them.

To turn it on once you have a paid account:

1. On developer.apple.com, create the iCloud container `iCloud.io.github.bradd06.lumen` (or in Xcode: Signing & Capabilities → + Capability → iCloud → CloudKit).
2. Add to `Config/Local.xcconfig`:
   ```
   LUMEN_CLOUDKIT_CONTAINER = iCloud.io.github.bradd06.lumen
   LUMEN_ENTITLEMENTS[sdk=iphone*] = Config/iCloud-iOS.entitlements
   LUMEN_ENTITLEMENTS[sdk=macosx*] = Config/iCloud-macOS.entitlements
   ```
3. Run `make open`, then build and run on two devices signed in with the same Apple ID. On iPhone, the sync status is in the Library, under the ⋯ menu in the top left corner.

</details>

## Built with

SwiftUI · GRDB (SQLite) · PDFKit · WebKit · PencilKit · ZIPFoundation · Swift Testing
