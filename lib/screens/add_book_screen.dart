import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_import/lumen_import.dart';
import 'package:material_ui/material_ui.dart';

import '../library/book_cover.dart';
import '../library/library_scope.dart';
import '../library/widgets.dart';
import '../shell/app_shell.dart';
import '../shell/tabs.dart';
import '../theme/glass.dart';
import '../theme/graphite.dart';
import 'book_screen.dart' show FactTile;
import 'tab_page.dart';

/// Вкладка «Добавить книгу»: выбрать файл (или перетащить на компьютере),
/// вставить текст. Добавленная книга сразу появляется в библиотеке.
class AddBookScreen extends StatefulWidget {
  const AddBookScreen({super.key});

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  bool _busy = false;
  bool _dragging = false;
  String? _error;
  Book? _added;

  Future<void> _run(Future<Book> Function(Library) add) async {
    final library = LibraryScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final book = await add(library);
      if (!mounted) return;
      setState(() => _added = book);
    } on ImportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('Книга не добавилась: $e');
      if (mounted) setState(() => _error = 'Книгу не удалось добавить. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    final List<PlatformFile> files;
    try {
      // На телефонах фильтр по расширению ломается на .fb2 — проверяем сами.
      files = isDesktop
          ? await FilePicker.pickFiles(
              dialogTitle: 'Выберите книгу',
              type: FileType.custom,
              allowedExtensions: supportedExtensions,
            )
          : await FilePicker.pickFiles(dialogTitle: 'Выберите книгу');
    } catch (e) {
      debugPrint('Выбор файла не открылся: $e');
      setState(() => _error = 'Не открылось окно выбора файла.');
      return;
    }
    final file = files.firstOrNull;
    if (file == null) return;
    await _run((library) async => library.addFile(file.name, await file.readAsBytes()));
  }

  Future<void> _dropped(DropDoneDetails details) async {
    setState(() => _dragging = false);
    final file = details.files.firstOrNull;
    if (file == null || _busy) return;
    await _run((library) async => library.addFile(file.name, await file.readAsBytes()));
  }

  Future<void> _pasteText() async {
    final result = await showDialog<(String, String)>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => const _PasteDialog(),
    );
    if (result == null) return;
    final (title, text) = result;
    await _run((library) => library.addText(text, title: title));
  }

  void _openLibrary() {
    setState(() => _added = null);
    TabSwitcher.of(context)(AppTab.library);
  }

  @override
  Widget build(BuildContext context) {
    final page = TabPage(
      title: 'Добавить книгу',
      children: [
        if (_added != null)
          _AddedCard(
            book: _added!,
            onOpen: _openLibrary,
            onMore: () => setState(() => _added = null),
          )
        else
          _DropZone(busy: _busy, dragging: _dragging, onTap: _pickFile),
        if (_error != null) _ErrorCard(text: _error!),
        Glass(
          radius: 22,
          child: Column(
            children: [
              // На iPhone и iPad книги чаще лежат в «Файлах»; большое поле выше
              // делает то же, но так понятнее.
              if (Platform.isIOS)
                _SourceRow(
                  icon: Icons24.file,
                  label: 'Из «Файлов» или iCloud Drive',
                  onTap: _busy ? null : _pickFile,
                ),
              _SourceRow(
                icon: Icons24.paste,
                label: 'Вставить текст',
                onTap: _busy ? null : _pasteText,
                last: true,
              ),
            ],
          ),
        ),
        const Text(
          'EPUB · FB2 · TXT · PDF',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Graphite.textMuted),
        ),
      ],
    );
    if (!isDesktop) return page;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _dropped,
      child: page,
    );
  }
}

/// Большое поле: нажать — выбрать файл; на компьютере файл можно бросить сюда.
class _DropZone extends StatelessWidget {
  const _DropZone({required this.busy, required this.dragging, required this.onTap});

  final bool busy;
  final bool dragging;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Выберите файл книги',
      child: FocusRing(
        radius: 28,
        onActivate: busy ? null : onTap,
        child: GestureDetector(
          onTap: busy ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 230,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: dragging ? Graphite.text : Colors.transparent, width: 1.5),
            ),
            child: Glass(
              radius: 28,
              fill: dragging ? Graphite.glassFillStrong : Graphite.glassFill,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0x24FFFFFF),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: busy
                          ? const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Graphite.text,
                              ),
                            )
                          : const LineIcon(Icons24.upload, size: 28),
                    ),
                    Text(
                      busy
                          ? 'Разбираю книгу…'
                          : (dragging ? 'Отпустите файл' : 'Выберите файл книги'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    if (!busy && isDesktop)
                      const Text(
                        'или перетащите его сюда',
                        style: TextStyle(fontSize: 13, color: Graphite.textMuted),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Книга добавлена: обложка, название, формат, главы и примерное время звука.
class _AddedCard extends StatelessWidget {
  const _AddedCard({required this.book, required this.onOpen, required this.onMore});

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final characters = book.chapters.fold(0, (sum, c) => sum + c.text.length);
    return Glass(
      radius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Row(
            spacing: 14,
            children: [
              SizedBox(width: 64, child: BookCover(book: book, radius: 10, titleSize: 9)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    const Text(
                      'Книга добавлена',
                      style: TextStyle(fontSize: 12, color: Graphite.textMuted),
                    ),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    if (book.author != null)
                      Text(
                        book.author!,
                        style: const TextStyle(fontSize: 13, color: Graphite.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: FactTile(label: 'Формат', value: bookFormat(book)),
              ),
              Expanded(
                child: FactTile(label: 'Глав', value: '${book.chapters.length}'),
              ),
              Expanded(
                child: FactTile(label: 'Звука', value: '≈ ${listeningTime(characters)}'),
              ),
            ],
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: AccentButton(label: 'В библиотеку', onPressed: onOpen),
              ),
              Expanded(
                child: OutlineButton(label: 'Добавить ещё', onPressed: onMore),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Glass(
    radius: 18,
    shadow: false,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      spacing: 12,
      children: [
        const LineIcon('M12 8v5M12 16.5v.01M12 3l10 18H2z', size: 20),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35))),
      ],
    ),
  );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.icon, required this.label, this.onTap, this.last = false});

  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Graphite.line)),
      ),
      child: Row(
        spacing: 12,
        children: [
          LineIcon(icon),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          const Text('›', style: TextStyle(fontSize: 17, color: Graphite.textMuted)),
        ],
      ),
    ),
  );
}

/// Окно «Вставить текст»: название и сам текст; кнопка вставляет из буфера.
class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _title = TextEditingController();
  final _text = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _fromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _text.text = text;
  }

  InputDecoration _field(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Graphite.textMuted),
    filled: true,
    fillColor: Graphite.glassFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Graphite.glassBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Graphite.glassBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Graphite.text),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Glass(
          radius: 26,
          fill: const Color(0xE61C1C24),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Вставить текст',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: _fromClipboard,
                    style: TextButton.styleFrom(foregroundColor: Graphite.text),
                    child: const Text('Из буфера'),
                  ),
                ],
              ),
              TextField(
                controller: _title,
                style: const TextStyle(color: Graphite.text),
                cursorColor: Graphite.text,
                decoration: _field('Название (необязательно)'),
              ),
              Flexible(
                child: TextField(
                  controller: _text,
                  minLines: 6,
                  maxLines: 12,
                  style: const TextStyle(color: Graphite.text, height: 1.4),
                  cursorColor: Graphite.text,
                  decoration: _field('Текст книги или рассказа'),
                ),
              ),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: OutlineButton(
                      label: 'Отмена',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: _text,
                      builder: (context, _) => AccentButton(
                        label: 'Добавить',
                        onPressed: _text.text.trim().isEmpty
                            ? null
                            : () => Navigator.of(context).pop((_title.text, _text.text)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
