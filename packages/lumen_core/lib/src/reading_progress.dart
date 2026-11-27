/// Точное место в главе: абзац (или картинка) по порядку и доля его высоты,
/// где проходит верх видимого текста. Не зависит от ширины окна и от того,
/// успели ли загрузиться картинки выше.
final class ChapterPlace {
  const ChapterPlace({required this.item, this.within = 0});

  /// Номер абзаца или картинки в главе (как в `chapterItems`).
  final int item;

  /// Сколько этого абзаца уже ушло вверх: от 0 до 1.
  final double within;

  @override
  bool operator ==(Object other) =>
      other is ChapterPlace && other.item == item && other.within == within;

  @override
  int get hashCode => Object.hash(item, within);

  @override
  String toString() => 'ChapterPlace($item, $within)';
}

/// Сколько прочитано в книге: доля каждой главы и глава, где читатель остановился.
final class ReadingProgress {
  const ReadingProgress({this.chapters = const {}, this.places = const {}, this.current});

  static const empty = ReadingProgress();

  /// Номер главы → прочитанная доля от 0 до 1 (место в главе).
  final Map<int, double> chapters;

  /// Точные места в главах (номер главы → место); у старых записей нет.
  final Map<int, ChapterPlace> places;

  /// Глава, которую открывали последней; `null` — книгу ещё не читали.
  final int? current;

  /// Доля главы [index]: 0, если её не открывали.
  double of(int index) => chapters[index] ?? 0;

  /// Глава дочитана до конца.
  bool finished(int index) => of(index) >= 0.99;

  /// Доля всей книги: главы весят по длине текста, все главы до текущей
  /// считаются прочитанными, после неё — нет.
  double ofBook(List<int> chapterLengths) {
    final current = this.current;
    if (current == null) return 0;
    final total = chapterLengths.fold(0, (sum, n) => sum + n);
    if (total == 0) return 0;
    var read = 0.0;
    for (var i = 0; i < chapterLengths.length; i++) {
      if (i < current) {
        read += chapterLengths[i];
      } else if (i == current) {
        read += chapterLengths[i] * of(i);
      }
    }
    return (read / total).clamp(0.0, 1.0);
  }

  /// Тот же прогресс, где глава [index] прочитана на [fraction] и стала текущей.
  ReadingProgress withChapter(int index, double fraction, {ChapterPlace? place}) => ReadingProgress(
    chapters: {...chapters, index: fraction.clamp(0.0, 1.0)},
    places: place == null ? ({...places}..remove(index)) : {...places, index: place},
    current: index,
  );
}
