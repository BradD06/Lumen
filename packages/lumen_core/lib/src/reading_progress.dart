/// Сколько прочитано в книге: доля каждой главы и глава, где читатель остановился.
final class ReadingProgress {
  const ReadingProgress({this.chapters = const {}, this.current});

  static const empty = ReadingProgress();

  /// Номер главы → прочитанная доля от 0 до 1 (место в главе).
  final Map<int, double> chapters;

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
  ReadingProgress withChapter(int index, double fraction) =>
      ReadingProgress(chapters: {...chapters, index: fraction.clamp(0.0, 1.0)}, current: index);
}
