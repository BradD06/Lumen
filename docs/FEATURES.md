# Lumen: что уже есть в приложении

Полный список готовых функций, сверенный **с кодом** в `main` (15 ноября 2026, после PR #82). Читай его перед любой новой задачей: если функция здесь есть, её не делают заново, а улучшают или чинят отдельной задачей.

- README, ROADMAP и память могут отставать. Если сомневаешься, проверь по пути в коде из строки (`grep` по названию кнопки тоже работает: строки интерфейса на русском).
- **Где:** «все» = Mac, iPad и iPhone. «Mac/iPad» = широкий экран (iPad в обычной ширине показывает тот же интерфейс, что Mac). «iPhone» = узкий экран, `Phone/PhoneRootView.swift`.
- Пути без префикса считаются от `Packages/LumenKit/Sources/`.
- Направление и планы (ИИ, датасеты, совместимость с Notion) описаны в [`PRODUCT_SCOPE.md`](PRODUCT_SCOPE.md), порядок работ в [`ROADMAP.md`](ROADMAP.md).
- **Как вести файл:** PR, который добавляет заметную пользователю функцию, добавляет сюда строку (вместе со строкой в Features в `README.md`). Большую работу, которая выкладывается по частям, можно держать в разделе «В работе (ещё НЕ в main)»; когда часть сливается в `main`, её строка переезжает в нужный раздел.

## Навигация и окно

| Функция | Где | Код |
|---|---|---|
| Остров внизу по центру окна: значки с подписями Стол, Записки (с числом неразобранных), Дела, Полка, «Поиск» (⌘K), «Создать» акцентом (щелчок: заметка, удержание: меню), «Ещё» (Архив, Настройки); ⌘, открывает Настройки. Открытый раздел выпрыгивает фиолетовым кружком над капсулой, под ним вырез; при переходе кружок с вырезом переезжает | Mac/iPad | `LumenUI/Navigation/Island.swift`, `Navigation/BubbleBar.swift`, `RootView.swift` |
| Капсула внизу iPhone во всю ширину: Стол, Записки, Дела, Полка, Поиск, Создать, с подписями и тем же кружком с вырезом; прячется в открытой заметке, книге и при поднятой клавиатуре | iPhone | `Phone/PhoneRootView.swift` (`PhoneTabCapsule`), `Navigation/BubbleBar.swift` |
| Капсула разделов внизу слева (Стол, Записки, Дела, Полка), круглые кнопки поиска и «+» справа; прячется в заметке, в книге и при открытой клавиатуре | iPhone | `LumenUI/Phone/PhoneRootView.swift` |
| Вкладки (⌘T, ⌘W, ⌘1…9, ⌃Tab), дублировать / закрыть другие | Mac/iPad | `Navigation/Workspace.swift`, `WorkspaceViews.swift` |
| «Назад / Вперёд» как в браузере (⌘[ ⌘]) у каждой вкладки | Mac/iPad | `Navigation/Workspace.swift` |
| Разделить экран на две панели (⌘\\), перетащить вкладку к краю, панели рядом или друг под другом, поменять местами, ⌥⌘← → между панелями | Mac/iPad | `Navigation/PaneSplit.swift`, `PaneLayout.swift`, `LumenCore/PaneArrangement.swift` |
| Ссылка из заметки открывается в соседней панели | Mac/iPad | `RootView.openLink(_:from:)` |
| Палитра команд ⌘K: поиск страниц, книг, цитат, недавнее, действия; ⌘↵ открывает рядом; на Mac закрывается щелчком мимо окна | все (на iPhone вкладка «Поиск») | `Navigation/CommandPalette.swift`, `Navigation/OutsideClick.swift`, `RootView.paletteExtras` |
| Управление без мыши: ⌘J ставит букву на всё, что нажимается; ⇧+буква открывает меню; работает в русской раскладке | Mac (iPad с клавиатурой) | `Navigation/KeyHints.swift` |
| Режим фокуса (⇧⌘F): прячет остров с разделами и вкладки, таймер учёбы 25 минут | Mac/iPad | `Navigation/FocusMode.swift`, `Editor/PageChrome.swift` |
| Лампа на полке «Стола»: затемняет края окна и включает таймер | все | `Library/StudyLamp.swift` |
| «Что показывать на экране»: полоса вкладок, кнопки назад/вперёд, «Сохранено», счётчик слов, путь, сетка библиотеки, карточки «Стола», полоса прогресса книги | все | `Navigation/ScreenOptions.swift` |
| Единая кнопка «Создать»: заметка (⌘N), задача (⇧⌘N), тетрадь, книга или файл (⌘O), база, папка | все | `Navigation/AppActions.swift` (`CreateKind`, `Creator`) |
| Значок-эмодзи у страницы, базы, папки | все | `Navigation/IconPicker.swift` |
| Настройки: синхронизация, оформление, звуки, что на экране, данные и копии | все | `Navigation/AppActions.swift` (`SettingsSheet`) |

## Стол, Входящие, корзина, поиск

| Функция | Где | Код |
|---|---|---|
| «Стол» (Сегодня): приветствие и поле «Записать мысль» с галочкой «Это задача»; последняя заметка большой карточкой (лист на её обложке, путь, начало текста, выдержки); задачи на сегодня; книга, которую читаешь, с кольцом минут за сегодня (открывает «Чтение»); папки с обложками цвета папки, плитка «Входящие» с кнопкой «Разобрать», «Новая папка»; полка недавних книг с лампой; недавние заметки | все | `LumenUI/HomeView.swift`, `HomeSnapshot` / `DeskNote` в `LumenStorage/Queries.swift` |
| Быстрая заметка из «Команд» (Shortcuts) и Siri, попадает во «Входящие» | все | `App/QuickNoteIntent.swift` |
| «Входящие» и разбор по одной: смахнуть, три предложенные папки, в задачи, оставить, удалить, отменить (⌘Z) | все | `LumenUI/InboxView.swift` (`InboxTriageView`) |
| Избранное | все | `Library/LibraryView+SystemMenu.swift`, `RootView.swift` |
| Архив (корзина): восстановить, удалить навсегда, очистка через 30 дней | все | `InboxView.swift`, `LumenStorage/TrashRepository.swift` |
| Полнотекстовый поиск по страницам, книгам и выделениям (FTS5) | все | `LumenStorage/Search.swift`, `LumenUI/SearchView.swift` |
| Всплывающие уведомления с «Вернуть» | все | `LumenUI/Notices.swift` |
| Тихие звуки (полка, лампа, скотч, лист, кнопка) и отклик вибрацией на iPhone; выключаются в Настройках | все | `LumenUI/LumenSounds.swift` |

## Блочный редактор

| Функция | Где | Код |
|---|---|---|
| Блоки: текст, заголовки 1–3, списки, задача, цитата, выноска, код, разделитель, страница, картинка, сворачиваемый, колонки, выписка, рисунок, новый лист, таблица, база данных | все | `LumenCore/BlockType.swift`, `Editor/BlockRow.swift` |
| Меню «/» с поиском по-русски и по-английски | все | `Editor/BlockRow.swift`, `BlockType.keywords` |
| Обложка за листом: картинка на всю ширину, первый лист лежит на её нижнем крае; «Ракурс»: тянуть картинку, щипок или ползунок для размера, высота полосы (низкая, средняя, высокая), «По центру»; «Сменить», «Убрать» | все | `Editor/PageCoverBand.swift`, `LumenCore/Page.swift` (`CoverCrop`, миграция v20) |
| Markdown-сокращения при наборе (`#`, `-`, `1.`, `[]`, `>`, ```` ``` ````, `---`) | все | `LumenCore/MarkdownShortcut.swift` |
| Оформление текста: жирный, курсив, подчёркнутый, зачёркнутый, код, ссылка; плавающая панель; ⌘B ⌘I ⌘U ⇧⌘X ⌘E; «Формат» в меню правой кнопки | все (на iPhone/iPad панель над клавиатурой) | `LumenCore/InlineMarkup.swift`, `Editor/FormatBar.swift`, `PageEditorModel+Format.swift` |
| Цвет текста и фона блока | все | `Editor/BlockColors.swift` |
| Вложенность Tab / ⇧Tab, перетаскивание блоков, колонки (бросить блок рядом); вынести блок из колонки на всю ширину: перетащить над или под ряд колонок, ⇧Tab или меню блока | все | `Editor/BlockTree.swift`, `PageEditorModel+Structure.swift` |
| Отмена и повтор (⌘Z / ⇧⌘Z), дублировать (⌘D), сохранение пачками | все | `Editor/PageEditorModel.swift` |
| Выделение нескольких блоков: рамка мышью (Mac), ручки с ⇧/⌘, Esc, ⌘A дважды; удалить, копировать, вырезать, вставить, дублировать, переместить (⌥⌘↑↓), вложить, превратить, цвет | все (рамка только Mac) | `LumenCore/BlockSelection.swift`, `Editor/BlockSelectionViews.swift`, `PageEditorModel+Selection.swift`, `BlockPasteboard.swift` |
| Меню блока (правая кнопка / два пальца): добавить ниже, превратить, цвет, скопировать текст, «в Задачи на сегодня», переместить, удалить | все | `Editor/BlockRow.swift` (`menu`) |
| Картинка: из файлов или фото, размер ручками (ширина, высота, угол), готовые размеры | все | `Editor/ImageBlock.swift`, `PageEditorModel+Media.swift` |
| Вложения: «Файл» (Quick Look), PDF прямо на странице, видео, аудио, закладка сайта; картинка из «Файла» становится «Картинкой»; PDF и книги открываются «В читалке» (в библиотеку один раз) | все | `Editor/AttachmentBlocks.swift`, `PageEditorModel+Attachments.swift`, `LumenCore/Attachment.swift` |
| Видео с YouTube в заметке: вставить ссылку в пустую строку (или `/видео` → «вставьте ссылку на YouTube»), превью с кнопкой, ролик играет прямо в блоке, на весь экран, с начала из ссылки (`t=`); название и автор под роликом, «На YouTube»; Shorts вертикально; ⌘Z возвращает ссылку текстом | все | `Editor/YouTubeEmbed.swift`, `LumenCore/YouTubeLink.swift` |
| Комментарии к любому блоку (меню блока → «Комментарий» или ⇧⌘M): значок с числом открытых, изменить, решить, удалить; текст комментариев ищется | все | `Editor/BlockComments.swift`, `PageEditorModel+Comments.swift`, `LumenCore/BlockComment.swift` |
| История версий страницы («Ещё» → «История версий…»): снимок раз в десять минут правки, хранится только на этом устройстве (таблица `pageVersion`), просмотр версии и возврат в один клик, ⌘Z отменяет возврат | все | `Editor/PageHistorySheet.swift`, `LumenStorage/PageVersionRepository.swift`, `LumenCore/PageVersionPolicy.swift` |
| Шаблоны страниц: пустая страница предлагает встроенные (конспект лекции, конспект книги, план недели, дневник, встреча) и свои; «Ещё» → «Сохранить как шаблон»; свои шаблоны синхронизируются (таблица `pageTemplate`) | все | `Editor/TemplateSuggestions.swift`, `PageEditorModel+Templates.swift`, `LumenCore/PageTemplate.swift`, `LumenStorage/PageTemplateRepository.swift` |
| Синхронные блоки (`/синхронный` или «Сделать синхронным» у выделенных): скопировать и вставить на другие страницы, правка в любой копии видна везде; копию можно отвязать в обычные блоки, вырезанный оригинал переезжает, не ломая копии | все | `Editor/SyncedBlockViews.swift`, `PageEditorModel+Synced.swift`, `LumenCore/SyncedBlock.swift` |
| Таблица на странице: Tab / Return, ширина столбцов, строка и столбец заголовков, меню ячейки | все | `Editor/TableBlock.swift`, `PageEditorModel+Table.swift`, `LumenCore/TableData.swift` |
| База данных на странице: новая, «Задачи» или существующая, все виды; «Открыть» на весь экран | все | `Editor/DatabaseBlock.swift` |
| Вставка Markdown раскладывается по блокам (заголовки, списки, задачи, цитаты, код, разделители, таблицы) | все | `LumenCore/MarkdownPaste.swift`, `PageEditorModel+Paste.swift` |
| Подсветка синтаксиса кода, видна прямо при наборе | все | `LumenCore/CodeSyntax.swift`, `Editor/CodeBlockBody.swift` |
| Формулы TeX: блок «Формула» (`/формула`, `/math` или `$$ ` в начале строки; сверху исходник, под ним формула меняется на ходу, Return выходит) и формула в строке `$$x^2$$` (⇧⌘E, кнопка на панели оформления); в Markdown `$$…$$` / `$…$`, в PDF картинкой; вёрстка SwiftMath | все | `Editor/MathViews.swift`, `LumenCore/InlineMarkup.swift` (`TextMark.math`), `LumenCore/MarkdownPaste.swift` |
| Ссылки на страницы через `[[` или `@`, подстраницы, обратные ссылки внизу страницы («Ссылки на эту страницу») | все | `LumenCore/MentionTrigger.swift`, `Editor/PageEditorView.swift`, `SubpagesPanel.swift` |
| Предпросмотр страницы по наведению (долгое нажатие на iPhone), предпросмотр выписки | все | `Editor/PageLinkPreview.swift` |
| Карта документа (заголовки страницы) | Mac/iPad | `Editor/PageOutlineView.swift` |
| Блок «Оглавление» (`/оглавление`, `/toc`): заголовки страницы с отступом по уровню, сам обновляется, щелчок прокручивает к заголовку; в Markdown и PDF это список заголовков | все | `Editor/TableOfContentsBlock.swift`, `LumenCore/PageContents.swift` |
| Заметка как листы A4: «Добавить лист», меню листа (выше, ниже, соединить, удалить, приколоть к полке), миниатюры слева, «Разложить по листам»; длинная заметка открывается сразу и листается плавно: листы достраиваются после открытия | все (миниатюры на широком экране) | `LumenCore/NoteSheets.swift`, `Editor/NoteSheetViews.swift`, `PageEditorModel+Sheets.swift`, `Editor/SheetLoading.swift` |
| Обложка страницы (градиенты темы или своё фото), фон страницы (горы или фото) | все | `Editor/PageBackgroundPicker.swift`, `LumenThemes/LayeredWallpaper.swift` |
| Путь над заголовком, «Сохранено», счётчик слов | все | `Editor/PageChrome.swift` |
| Панель над клавиатурой (новый блок, вложить, переместить, спрятать клавиатуру) и чипы типов блоков | iPhone | `Editor/PageEditorView.swift`, `PageChrome.swift`, `EmptyBackspace.swift` |
| Экспорт страницы в Markdown и PDF | все | `LumenStorage/Export.swift`, `LumenCore/PageExport.swift`, `Export/` |

## Читалка и книги

| Функция | Где | Код |
|---|---|---|
| Форматы: EPUB, PDF, FB2, CBZ, DOCX, PPTX, RTF, TXT, Markdown, HTML; DOC и ODT только на Mac; остальное через Quick Look | все | `LumenReader/ReadableDocument.swift` (`DocumentConverter`), конвертеры `*Converter.swift`, `QuickLookView.swift` |
| Открыть файл из «Файлов», Telegram, Почты, Finder, бросить на иконку в Dock; ссылки `lumen://` | все | `LumenUI/Incoming/`, `App/LumenApp.swift`, `LumenCore/LumenLink.swift` |
| Выделения 5 цветами, заметка к выделению, список выделений (⌥⌘L), оглавление (⌥⌘T) | все | `Reader/ReaderSelectionBars.swift`, `HighlightNote.swift`, `ReaderSidePanels.swift` |
| Выписка в заметку (⌘E) со ссылкой на точное место; перетащить «В заметки» на любую открытую заметку | все | `Reader/ReaderModel.swift`, `ExcerptDrag.swift` |
| **Перевод выделенного текста** (встроенный перевод Apple) и «Ссылка» на место в панели выделения | все | `Reader/ReaderSelectionBars.swift` |
| Заметки рядом с книгой (на iPhone выезжают снизу), переключатель «Текст / Перо», кнопка «ссылка на это место», любая другая страница рядом | все | `Reader/ReaderView+Notes.swift`, `SidePagePicker.swift` |
| «Окна»: книга и заметки рядом или друг под другом, запоминается для каждой книги | Mac/iPad | `Navigation/PaneLayout.swift`, `Reader/ReaderLayoutStore.swift` |
| Оформление: темы «Ночь», «Бумага», «Рассвет», «Как в файле», шрифт (засечки, гротеск, округлый), размер 14–48 | все | `Reader/ReaderChrome.swift`, `LumenReader/ReaderScript.swift` (`ReaderAppearance`) |
| Точное место чтения запоминается; полоса прогресса | все | `Reader/ReaderModel.swift` |
| Листание свайпом, двумя пальцами на трекпаде, стрелками; ⌥⌘← → между книгой и заметками | все (клавиши на Mac) | `LumenReader/PDFReader.swift`, `Reader/ReaderKeys.swift` |
| PDF «Текст / Оригинал»: перекладка в главы, без колонтитулов, выноски цветными рамками | все | `LumenReader/PDFTextConverter.swift`, `PDFTextLayout.swift` |
| PDF: обрезка полей, чтение по колонкам, свой масштаб для книги, тонировка страниц в тёмной теме | все | `LumenReader/PDFPageLayout.swift`, `PDFPageTint.swift`, `PDFReader.swift` |
| Панель книги: время, «Осталось» и «Дочитаешь», серия, календарь дней, сеансы | все | `Reader/SourceDashboardView.swift`, `LumenCore/ReadingInsights.swift` (`ReadingForecast`) |
| Экран «Чтение» по всем книгам: цель на день, неделя/месяц/год, рекорд, прочитанные за год | все | `Reader/ReadingOverviewView.swift`, `ReadingWidgets.swift`, `LumenCore/ReadingInsights.swift` (`ReadingOverview`) |
| Заметки к книге лежат в папке книги и создаются, когда их начинают | все | `ReaderModel.ensureNotes()` |
| Одна книга, добавленная на двух устройствах, сливается в одну | все | `LumenCore/BookDuplicates.swift`, `LumenStorage/BookDuplicatesRepository.swift` |

## Библиотека и полки

| Функция | Где | Код |
|---|---|---|
| Библиотека-холст: страницы, тетради, книги, папки; сетка с примагничиванием; перетащить файл, чтобы добавить | Mac/iPad | `Library/LibraryView*.swift`, `LibraryTiles.swift` |
| Библиотека списком | iPhone | `Library/LibraryCompactList.swift` |
| Папки с цветом и значком, «Переместить в…» | все | `Library/MoveToFolderSheet.swift`, `LumenCore/Folder.swift` |
| Книжные полки: корешки (кожа, ткань, мягкая обложка), позы, закладки-ленты, потёртость у прочитанных; несколько полок (полка = папка); перетаскивание; сортировка | все | `Library/BookShelf.swift`, `LumenCore/ShelfSort.swift` |
| «Читаю сейчас» над полками: обложка, прочитано / осталось / дочитаю, «Продолжить», «С заметками рядом», последняя выдержка, заметки к книге, «Тоже читаю» | все | `Library/ShelfReadingNow.swift`, `ShelfReadingSnapshot` в `LumenStorage/ReadingRepository.swift` |
| Кнопки над полками «Все · Читаю · Хочу · Прочитано» с числом книг (кроме «Все» одна полка без перетаскивания); число выделений внизу корешка | все | `Library/BookShelf.swift` (`ShelfStatusPicker`), `LumenCore/ShelfSort.swift` (`ShelfStatus`) |
| Вид полки «Корешки · Обложки · Список» (запоминается, `shelf.display`); поиск «Книга или автор» (одна полка с найденным); порядок в меню рядом | все | `Library/BookShelf.swift`, `Library/ShelfViews.swift`, `LumenCore/ShelfDisplay.swift` (`ShelfDisplay`, `ShelfSearch`) |
| Плитка «Перетащите сюда файл книги» в конце каждой полки: файл из Finder или «Файлов» становится книгой на этой полке, нажатие открывает выбор файла | все | `Library/ShelfViews.swift` (`ShelfDropTile`, `ShelfFileDrop`) |
| Книга «вылетает» с полки в витрину с обложкой и карточкой статистики | все | `Library/BookShowcase.swift`, `BookStatsCard.swift` |
| Своя обложка: файл, ⌘V, перетаскивание, камера, Фото; выбор полоски для корешка; вернуть обложку из книги | все | `Library/BookCover.swift` |
| Листы заметок на полке: папки-скоросшиватели, лоток одиночных листов, приколотые листы | все | `Library/ShelfSheets.swift` |

## Рукописные заметки

| Функция | Где | Код |
|---|---|---|
| Тетради с листами: тон бумаги, масштаб листов | все | `Drawing/NotebookView.swift`, `LumenCore/Notebook.swift` |
| Шаблоны листов: чистый, линейка, клетка, мелкая клетка 5 мм, точка, конспект Корнелла, план недели, нотный стан; для всей тетради или одного листа (меню «Листы», на Mac правый щелчок по листу); новый лист берёт шаблон предыдущего | все | `PaperPattern` в `LumenCore/Notebook.swift`, `BlockContent.sheetPapers` + `NotebookSheets.paper`, рисует `PaperGeometry` в `Drawing/DrawingSupport.swift` |
| Ровные фигуры: линия, круг, эллипс, треугольник, прямоугольник, много­угольник; задержать перо в конце штриха (0,5 с) или режим «Фигуры» (кнопка рядом с пером, UserDefaults `drawing.shapes`) | все | `LumenCore/ShapeRecognizer.swift`, `Drawing/ShapeSnapping.swift` |
| Перо, маркер, палитра цветов, текст и картинки на листе (файл, фото, буфер) | все | `Drawing/NotebookItemsViews.swift`, `DrawingColors.swift`, `NotebookPasteboard.swift` |
| Apple Pencil и палец | iPad, iPhone | `Drawing/PencilCanvas.swift` |
| Рисование мышью и трекпадом | Mac | `Drawing/MouseDrawing.swift` |
| Лассо: выделить, переместить, растянуть, повернуть (прилипает к углам через 15°), перекрасить, выровнять в ровные фигуры, дублировать, удалить | Mac (на iPad и iPhone системное лассо PencilKit) | `Drawing/DrawingLasso.swift`, `Drawing/MouseDrawing.swift` |
| Страницы PDF и книг из библиотеки как листы тетради | все | `Drawing/SheetPDFImages.swift` |
| Миниатюры листов (кнопка в шапке тетради): нажать, чтобы открыть лист; перетащить, чтобы переставить; меню: дублировать, новый лист, выше / ниже, удалить. На Mac и iPad колонка слева, на iPhone сетка в окне | все | `Drawing/NotebookSheetStrip.swift`, `moveNotebookSheet` / `duplicateNotebookSheet` в `Editor/PageEditorModel+Drawing.swift` |
| Поиск по почерку: написанное от руки читается на устройстве (Vision, русский и английский) через 2 с после того, как перестали писать; тетрадь находится в общем поиске ⌘K по этим словам и по текстам на листах; лупа в шапке тетради показывает, на каких листах слово | все | `Drawing/HandwritingReader.swift`, `BlockContent.sheetTexts`, `NotebookSheets.matches` в `LumenCore/NotebookSheetEdits.swift` |
| Блок «Рисунок» внутри обычной заметки | все | `Drawing/DrawingBlock.swift` |

## Базы данных и задачи

| Функция | Где | Код |
|---|---|---|
| Базы: свойства текст, число, выбор, несколько вариантов, статус, дата, флажок, ссылка на страницу | все | `LumenCore/DataTable.swift`, `Database/PropertyViews.swift` |
| Виды: таблица, доска, календарь, список; несколько представлений, группировка, фильтры (в т. ч. «сегодня», «через неделю»), сортировка | все | `Database/DataLayouts.swift`, `DataTableScreen.swift`, `DataQuery` в `LumenCore/DataTable.swift` |
| Столбцы-формулы: значение из других столбцов строки (`{Цена} * {Количество}`, `if({Готово}, "✓", "")`, дни до срока), русские слова («если», «и», «сегодня»), проверка на первой строке при наборе, фильтр и сортировка как у любого столбца | все | `LumenCore/Formula.swift`, `Database/FormulaEditor.swift` |
| Запись открывается как страница | все | `Database/DataTableModel.swift` |
| Связи между базами: столбец «Связь с базой» отмечает строки другой базы (или этой же), с поиском и созданием строки на месте; по желанию двусторонняя (в той базе своя обратная колонка, обе всегда совпадают); фильтр «содержит строку» | все | `LumenCore/DataRelation.swift`, `Database/RelationViews.swift`, `DataTableRepository` (`addRelation`, `setRelationTwoWay`) |
| Сводки по связи (rollup): количество, заполнено, разных, сумма, среднее, мин/макс, ранняя/поздняя дата, «готово» штук и %, значения через запятую; формулы видят сводки | все | `LumenCore/DataRelation.swift` (`Rollup`), `Database/RelationViews.swift` (`RollupSetupSheet`) |
| Трекер задач («Дела»): готовая база-шаблон `tasks` с видами Сегодня, Доска, Все, Календарь | все | `SidebarItem.tasks`, `LumenStorage/DataTableRepository.swift` |

## Оформление

| Функция | Где | Код |
|---|---|---|
| Единственный вид «Остров»: ровный фон, белые (в тёмной теме графитовые) листы, стеклянный остров, один сиреневый акцент | все | `LumenThemes/Components.swift`, `Theme.swift` |
| Оформление: «Как в системе · Светлая · Тёмная» в Настройках | все | `Theme.light` / `Theme.dark`, `AppearanceMode`, `Navigation/ThemeSettings.swift` |
| Окно в цвет обложки открытой заметки (фон, свет, акцент); выключатель в Настройках → «Обложки», по умолчанию включено | все | `Editor/CoverTint.swift`, `LumenThemes/CoverTinting.swift`, `Navigation/ThemeSettings.swift` |
| Плавные анимации, с «Уменьшением движения» становятся затуханием | все | `LumenThemes/Motion.swift` |

## Данные и синхронизация

| Функция | Где | Код |
|---|---|---|
| Бесплатная синхронизация через iCloud Drive (папка «Lumen Sync»), на Mac одной кнопкой, состояние под приветствием «Стола» | все | `LumenSync/FolderSyncController.swift`, `LumenStorage/FolderSync*.swift`, `LumenUI/SyncSetupViews.swift`, `SyncStatusRow.swift` |
| Резервная копия (с книгами и картинками или без) и восстановление; автоматические копии перед обновлением и восстановлением | все | `LumenStorage/Backup.swift`, `Backup/DataSafetyView.swift` |
| Экран восстановления, если база не открылась | все | `Backup/DatabaseRecoveryView.swift` |
| CloudKit-синхронизация написана, но **выключена** в обычной сборке (нужен платный аккаунт) | — | `LumenSync/CloudSync.swift` |

## Чего в коде нет (проверено 15.11.2026)

Чтобы не думать, что это уже сделано:

- ИИ и подключение нейросетей, экспорт датасетов.
- Supabase, вход по почте / Google / Apple, совместная работа, публикация страниц.
- Виды баз «галерея» и «таймлайн», импорт из Notion.
- Перевод выделенного текста **в редакторе заметок** (есть только в читалке).
- Магазин виджетов и тем, приложение для Windows.
- Флеш-карточки и интервальное повторение: владелец отказался, не делать.
- Доска связей (пробковая доска с приколотыми заметками и нитками): владелец убрал её 16.11.2026, не возвращать. Таблица `boardPin` (миграция v15) осталась в базе без дела, чтобы старые данные и синхронизация не ломались.
