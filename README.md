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

Lumen takes the flexible block pages of Notion and puts your reading next to them. Open a book or any document, read it in the app, and write notes beside it. Every quote you save remembers the exact spot in the book it came from, so one tap takes you back there. Write by hand like in a paper notebook, track your tasks in databases, and keep everything in the "Study" look: a home library with books on shelves behind frosted glass.

## Features

### ✍️ Block notes
- A block editor with paragraphs, headings, lists, to-dos, quotes, callouts, code blocks with syntax highlighting, dividers, images and toggles.
- Notes are written on A4 sheets, not on an endless page. When a sheet is full, "Add sheet" under it starts the next one; a note that has outgrown its sheet (for example, from an older version) is laid out on sheets with one button. Each sheet has a menu to move it up or down, join it with the sheet above, delete it or pin it to the shelf. On a wide screen, sheet thumbnails on the left jump to any sheet; in the notes beside a book, sheet numbers and a + sit in the panel header.
- Markdown shortcuts (`#`, `-`, `1.`, `[]`, `>`, ```` ``` ````, `---`) and a `/` command menu.
- Nested blocks with Tab / ⇧Tab, drag-and-drop reordering, and columns: drop a block next to another one to place them side by side.
- Text and background colors, duplicate (⌘D), full undo and redo (⌘Z / ⇧⌘Z).
- Inline formatting: **bold**, *italic*, underline, ~~strikethrough~~, `code` and links. Select text and a floating format bar appears (on iPhone and iPad it sits above the keyboard), or use ⌘B, ⌘I, ⌘U, ⇧⌘X, ⌘E and the Format menu on right-click. While you edit a block you see light Markdown-style markers, and the block shows the finished formatting as soon as you leave it.
- A tidy right-click (two-finger tap) menu on every block: add a block below, turn into, color, copy text, send to today's tasks, move, delete. A `+` next to the drag handle adds a block on the Mac.
- Breadcrumbs above the title, a "Saved" indicator, a word count (each can be turned off), and a focus mode (⇧⌘F) that hides everything except the paragraph you are writing, with a 25-minute study timer that reminds you to take a break.
- Hover over an excerpt to preview the book and the place it came from. Hover over a link to a page (or long-press it on iPhone) to see how that page starts, then open it here or beside the current one.
- On iPhone, a keyboard bar (new block, indent, move, hide keyboard) and block-type chips above it.
- Subpages and links to any page with `[[` or `@`, plus backlinks at the bottom of every page.
- Page covers from the theme's gradients or your own photos.
- One **Create** button for everything: note (⌘N), task (⇧⌘N), handwritten notebook, book or file (⌘O), database, folder. On iPhone it is a round `+` button.
- Quick note with ⌘N, from Shortcuts or from Siri. It lands in the Inbox to sort later.
- A ⌘K command palette: search pages, books and quotes, open recent items, and run actions (⌘↵ opens a result beside the current one): tabs and panes, go back and forward, and act on the open note or book (favorite, move to a folder, copy its link, delete).
- Use the whole app without a mouse: ⌘J puts a short letter on everything you can click (cards, tiles, books on the shelf, list rows, tabs, buttons, settings), type the letter to press it, and ⇧ with the letter opens that item's menu. It works with a Russian keyboard layout too, since it goes by the key, not the letter.

### 📚 Reader for almost any file
- Read **EPUB, PDF, FB2, CBZ, Word, PowerPoint, RTF, ODT, Markdown, HTML and plain text** right inside the app. Other files open with Quick Look.
- Open books from Files, Telegram, Mail or Finder with "Share" / "Open with" → Lumen, or drop a file onto the Dock icon.
- Highlights with comments. Save a quote as an excerpt, and it links back to the exact place in the book.
- The selection bar also copies a link to the quote and translates the selected text with Apple's built-in translation.
- A **Text / Pen** switch in the notes beside a book: write with the keyboard, or draw at the end of the note.
- Bookmark a place while you write notes, and jump back to it later.
- Notes open beside the book in a split view. On iPhone they slide up as a sheet.
- A **Windows** switch on the Mac and iPad puts the book and its notes side by side or one above the other (book on top, note below), and swaps them. Drag the handle between them to resize. Each book remembers its layout, and an iPad held upright stacks them on its own. Split-screen panes can be stacked the same way.
- Drag a quote into a note: select text in the book and drag the "To notes" button onto any open note. It lands there as an excerpt that links back to the page.
- Lumen remembers exactly where you stopped reading. Dark mode tints PDF pages too.
- Read a PDF like an EPUB: the **Text** view reflows it into chapters (from the PDF's bookmarks or its large headings), keeps its pictures in place, drops running headers and page numbers (even when the header is the current section's name), sets notes, warnings and grey sidebars apart as coloured boxes, and lets you pick any font and size. Highlights, excerpts and your reading place carry over between the Text and Original views.
- Text size goes up to 48 pt in books and documents.
- Read the Original view of a PDF comfortably on a phone: Lumen trims the white margins of every page on its own (mirrored book margins included, stray watermarks ignored) so the text is larger at the same width, can read a two-column page column by column (left column fills the screen, then the right one), and remembers your zoom for each book. Scrolling stays straight up and down, without drifting sideways.
- Turn pages with a swipe: on iPhone and iPad by finger, on a Mac with a two-finger swipe on the trackpad, in books and in PDFs. Or with the arrow keys ← → ↑ ↓ (a zoomed PDF page scrolls first, then turns). ⌥⌘← and ⌥⌘→ move the keyboard between the book and the note beside it.
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
- A visual library for pages, notebooks, books and folders. Notes made from a book stay right next to it. Give any folder, note or database its own emoji icon (pick one or type any), and folders always stand out from the background.
- Browser-style back and forward, tabs (⌘T, ⌘1…9, ⌃Tab and ⌃⇧Tab to the next and previous tab) and split screen on Mac and iPad (⌥⌘← and ⌥⌘→ jump between the two halves). Drag a tab to one side of the window to open it next to another one.
- A **link board**: a corkboard (the Board room) where you pin books, folders and notes, and the links between them are drawn as red thread: page links, `lumen://` links, excerpts and book notes. A pinned folder stands in for everything inside it. Click a card to light up its threads, or show only its topic; drag a thread from one pin to another card and the link is written into the note. Pin things from the board, from a library item's menu or from ⌘K; the board syncs like everything else. On iPhone it opens from the Shelf.
- Favorites, an Inbox for quick notes, and a trash you can restore from.
- Sort the Inbox one note at a time: swipe, pick one of three suggested folders, turn a note into a task, keep it or delete it. Changed your mind? "Undo" (⌘Z) brings the last note back.
- Export a page to Markdown or PDF, plus full backups of your data.
- Free sync between Mac, iPhone and iPad through your iCloud Drive: notes, books, pictures, highlights and reading time follow you. Turn it on with one button on Today or at the top of Settings. On Mac that is all (Lumen finds iCloud Drive itself); on iPhone and iPad you tap iCloud Drive and "Open" once. Lumen then tells you which devices it found (or what to do on the next one), warns you if the chosen folder is not in iCloud Drive, and a line under the greeting on Today shows whether everything is synced; tap it to sync right away. A book you had added on two devices before syncing is merged into one, with its highlights, notes and reading place kept. No paid Apple account needed.
- On iPhone: Today, Inbox, Library and Search tabs at the bottom of the screen.

### 🌅 Design
- The "Study" look: a home library behind frosted glass, with a softly blurred bookcase and a warm lamp glow in the background, glass cards and glass shelves. Six color schemes in Settings → Appearance: Emerald (dark green and brass), Midnight, Cherry, Walnut, Dusk and the light Linen. Optionally the scheme can follow the time of day (for example Linen by day, Emerald in the evening, Midnight at night); this is off until you turn it on.
- A glass capsule of rooms along the top instead of a sidebar: Desk, Shelf, Board, Notes, Tasks, Archive (on iPhone they are the tabs at the bottom). Books stand on a shelf as spines cut from the middle of their covers (or in the cover's colors) in mixed bindings: leather with raised bands and gilt titles, cloth, and paperbacks; the title always runs along the spine, most books stand upright while some lean on their neighbours or lie on their side (a book you pick up straightens first), finished books look well read, and a brass bookend closes each row. A ribbon bookmark on each spine shows how far you have read; make your own shelves (each shelf is a folder in the library) with a + on every shelf to add a book right there, drag books between them, or use "Move to shelf", "Take off the shelf" and "Move to Trash" in a book's menu; drag books to put them in your own order, or sort the shelf by title, author, progress, last read or date added with the buttons above it; hover over a book and it slides off the shelf and turns its cover to you; click it and it flies to the middle of the window as a large cover with a translucent panel beside it: reading time, when you last read it, highlights and the notes with its quotes. Quotes from books sit in notes like clippings pasted into a notebook. Notes stand on the shelves next to the books: a note of two or more sheets is a ring binder (thicker the more sheets it has), single sheets lie in a glass tray at the end of the shelf (click it to see them all), and a pinned sheet hangs under the shelf on a brass pin and opens right at that sheet.
- Change a book's cover: by default it comes from the book as before, but you can put your own photo on it. On the Mac pick a file, paste with ⌘V or drop a picture onto the cover, and move a frame to choose which strip of the cover becomes the spine. On iPhone and iPad long-press a book for the camera, Photos, Files or the clipboard. "Change cover" is also in the panel of a book taken off the shelf, and "Restore the book's cover" brings the original back at any time. Your photo syncs with the book.
- A calm screen by default: Settings → "What to show on screen" brings back only what you want. The tab bar appears once you open a second tab, the back, forward and split buttons give way to ⌘[, ⌘] and ⌘\, "Saved" shows for a couple of seconds after an edit, and the word count, the page path, the library grid, each Today card and the book progress bar (always or on hover) can be turned on or off. The library has a single "Create" button.
- A desk lamp on the Today shelf: switch it on and the rooms and tabs step away, the edges of the window dim, and a 25-minute study timer starts; switch it off and the light comes back.
- Quiet sounds, on by default and easy to turn off in Settings: a book sliding onto the shelf, the lamp's switch, tape when an excerpt sticks to a note, paper rustling.
- The Desk (Today) shows one shelf of the books you read most recently, newest on the left; "All books" opens the full shelves.
- A **Today** screen: a capture field (tick "This is a task" to add it to today's tasks), Continue reading, today's tasks you can check off, the Inbox, and recent pages.

## Roadmap

Coming next, in order: reminders for tasks, more page styles, built-in widgets for the home screen, sync across devices with Supabase (including a future Windows app), Sign in with Apple, and a store for widgets and themes. The full plan, in Russian, is in [docs/ROADMAP.md](docs/ROADMAP.md), with one issue per step.

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
    LumenThemes/        design tokens, the "Study" theme, backgrounds, widget cards
    LumenReader/        reader: EPUB, FB2, PDF, Word, PowerPoint and text converters
    LumenSync/          sync: through an iCloud Drive folder, or CloudKit with a paid account
    LumenUI/            screens: home, inbox, rooms bar, library, editor, reader,
                        handwriting, databases, search; Phone/ holds the iPhone tabs
  Tests/                tests written with Swift Testing
UITests/                macOS UI tests (XCUITest)
project.yml             Xcode project definition for XcodeGen
.github/workflows/      CI: package tests, iOS and macOS builds, UI tests
```

## Sync

Your data stays on your device until you turn on sync. Sync works through a folder you pick yourself, usually iCloud Drive, so it needs no paid Apple Developer Program account. Later the plan is to add Supabase, which will also work with the future Windows app.

**Turn it on:** tap "Turn on sync" on the Today screen, or at the top of Settings (also in Data and backups). On Mac, Lumen uses iCloud Drive right away. On iPhone and iPad, a folder picker opens: tap iCloud Drive, then "Open". Do the same on every device. Lumen creates a `Lumen Sync` folder in iCloud Drive.

<details>
<summary>How folder sync works</summary>

Every change in the database (a page, block, folder, book, highlight or reading session) is added to a `syncChange` queue by SQLite triggers, and a `syncClock` table remembers when each row was last changed or deleted. A shared SQLite file in the cloud would get corrupted when two devices write to it, so every device keeps its own database and the folder holds only changes:

```
Lumen Sync/
  format.json
  devices/<device>/device.json            device name, last seen
  devices/<device>/changes/0000000001.json  changes in order (JSON)
  devices/<device>/snapshot-0000000300.json one compact copy instead of old changes
  files/<name>                            books, covers, pictures
```

Each device writes only into its own folder, so iCloud never has to resolve conflicts. A device reads the others' changes in order at launch, a few seconds after an edit, every 30 seconds while open, and when it comes back to the foreground. Of two edits to the same row, the later one wins, and a deletion is not undone by an older copy. Search and backlinks are rebuilt on each device. The engine is `FolderSyncEngine` (LumenStorage), and `FolderSyncController` (LumenSync) keeps the folder bookmark and runs it.

</details>

<details>
<summary>CloudKit sync with a paid account</summary>

The `LumenSync` module can also hand the same queue to `CKSyncEngine` and keep data in the user's private CloudKit database, with book files as assets. In a build with CloudKit, folder sync is hidden.

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
