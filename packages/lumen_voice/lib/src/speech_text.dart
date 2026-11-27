import 'package:lumen_core/lumen_core.dart';

import 'language.dart';
import 'sentences.dart';

/// Кусок главы: абзац, заголовок или код. `start` — место в тексте главы в UTF-16,
/// поэтому часть потом можно подсветить и запомнить как место.
/// Пропущенное внутри куска (сноски, номера страниц) заменено пробелами той же длины.
final class SpeechBlock {
  const SpeechBlock({
    this.kind = SpeechBlockKind.text,
    required this.text,
    this.raw,
    required this.start,
  });

  /// Абзацы главы: `paragraphs` — места абзацев в `text` (как `Chapter.paragraphs`).
  /// Нет абзацев — каждая непустая строка текста становится абзацем.
  static List<SpeechBlock> paragraphs(String text, [List<TextRange> paragraphs = const []]) {
    if (paragraphs.isNotEmpty) {
      return [
        for (final p in paragraphs)
          if (p.end <= text.length) SpeechBlock(text: p.of(text), start: p.start),
      ];
    }
    final result = <SpeechBlock>[];
    var start = 0;
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) result.add(SpeechBlock(text: line, start: start));
      start += line.length + 1;
    }
    return result;
  }

  final SpeechBlockKind kind;
  final String text;

  /// Текст как в книге, со сносками (той же длины, что `text`).
  final String? raw;
  final int start;
}

enum SpeechBlockKind { text, heading, code }

/// Часть текста, которую голос говорит целиком и которая подсвечена, пока звучит: предложение
/// (или абзац у голоса, который читает абзацами, см. `SpeechText.ramped`).
final class SpeechPart {
  const SpeechPart({
    required this.spoken,
    String? raw,
    required this.start,
    required this.length,
    this.isHeading = false,
  }) : raw = raw ?? spoken;

  /// Что сказать: без переносов, лишних пробелов и номеров сносок.
  final String spoken;

  /// Тот же кусок, как он стоит в тексте главы.
  final String raw;

  /// Где часть в главе (UTF-16) и сколько знаков главы подсветить.
  final int start;
  final int length;
  final bool isHeading;

  int get end => start + length;
  TextRange get range => TextRange(start, length);

  SpeechPart _withLength(int value) =>
      SpeechPart(spoken: spoken, raw: raw, start: start, length: value, isHeading: isHeading);

  @override
  bool operator ==(Object other) =>
      other is SpeechPart &&
      other.spoken == spoken &&
      other.raw == raw &&
      other.start == start &&
      other.length == length &&
      other.isHeading == isHeading;

  @override
  int get hashCode => Object.hash(spoken, raw, start, length, isHeading);

  @override
  String toString() => 'SpeechPart($start+$length «$spoken»)';
}

/// Текст главы для чтения вслух: куски → части (предложения) со своими местами в главе.
/// Очень длинное предложение режется по запятым. Код не читается, вместо него
/// «Пример кода пропущен.». Голые номера страниц и строки из одних знаков пропускаются.
abstract final class SpeechText {
  static const codeNotice = 'Пример кода пропущен.';

  /// Длиннее предложение режется по запятым: подсветка не стоит на месте полминуты.
  static const maxPartLength = 320;

  /// Самый длинный абзац одной частью у голоса, который читает абзацами.
  static const paragraphLength = 600;

  /// Насколько каждая следующая часть может быть длиннее: доля уже прочитанного после старта.
  /// Брэд (27.11.2026): озвучивать абзацами ради цельной интонации, поэтому разгон быстрый —
  /// одно предложение, потом части удваиваются и через 2–3 шага становятся целыми абзацами.
  static const rampGrowth = 1.0;

  /// Части по предложениям. `groupLength` склеивает соседние предложения абзаца в одну часть,
  /// пока она короче этого числа знаков (0 — каждое предложение отдельно).
  static List<SpeechPart> parts(List<SpeechBlock> blocks, {int groupLength = 0}) =>
      _parts(blocks, _Grouping(limit: groupLength));

  /// Части абзацами для голоса с сервера, который озвучивает лишь чуть быстрее речи. С места
  /// `startingAt` идёт одно предложение, а дальше части растут: каждая не длиннее первой плюс
  /// `growth` от уже прочитанного, пока не станут целыми абзацами до `limit` знаков. Пока звучат
  /// первые части, сервер успевает приготовить следующие. Части не переходят через границу
  /// абзаца; до места старта текст идёт абзацами.
  static List<SpeechPart> ramped(
    List<SpeechBlock> blocks, {
    required int startingAt,
    int limit = paragraphLength,
    double growth = rampGrowth,
  }) => _parts(blocks, _Grouping(limit: limit, rampStart: startingAt, growth: growth));

  static List<SpeechPart> _parts(List<SpeechBlock> blocks, _Grouping grouping) {
    final result = <SpeechPart>[];
    for (final original in blocks) {
      // Переносы строк внутри абзаца (в EPUB их полно) приняли бы за конец предложения:
      // заменяем их пробелами той же длины, места в главе не меняются.
      final text = flattened(original.text);
      final raw = original.raw ?? original.text;
      switch (original.kind) {
        case SpeechBlockKind.code:
          final length = text.length;
          if (length == 0 || !hasWords(text)) continue;
          // Несколько блоков кода подряд говорим один раз.
          if (result.isNotEmpty &&
              result.last.spoken == codeNotice &&
              original.start - result.last.end < 4) {
            final last = result.last;
            result[result.length - 1] = last._withLength(original.start + length - last.start);
            continue;
          }
          result.add(SpeechPart(spoken: codeNotice, start: original.start, length: length));
          grouping.counted(result.last);
        case SpeechBlockKind.heading:
          if (isNoise(text)) continue;
          final range = _trimmed(text, (start: 0, end: text.length));
          if (range == null) continue;
          result.add(_part(text, raw, original.start, range, isHeading: true));
          grouping.counted(result.last);
        case SpeechBlockKind.text:
          if (isNoise(text)) continue;
          final pieces = [for (final s in sentenceSpans(text)) ..._cut(text, s)];
          for (final piece in grouping.group(text, pieces, original.start)) {
            final range = _trimmed(text, piece);
            if (range == null) continue;
            final made = _part(text, raw, original.start, range, isHeading: false);
            if (hasWords(made.spoken)) result.add(made);
          }
      }
    }
    return result;
  }

  /// Часть, на которой стоит место `offset`: первая, что кончается после него.
  static int? indexOf(int offset, List<SpeechPart> parts) {
    var low = 0;
    var high = parts.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (parts[middle].end <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low < parts.length ? low : null;
  }

  /// Предложение части `part`, на котором стоит место `offset`: голос может читать целыми
  /// абзацами, а подсветка всё равно идёт по предложениям (`sentences` — результат `parts`).
  /// Не нашлось — вся часть.
  static TextRange sentenceAt(int offset, SpeechPart part, List<SpeechPart> sentences) {
    final whole = part.range;
    final found = indexOf(offset < part.start ? part.start : offset, sentences);
    if (found == null) return whole;
    final sentence = sentences[found];
    final start = sentence.start > part.start ? sentence.start : part.start;
    final end = sentence.end < part.end ? sentence.end : part.end;
    return start < end ? TextRange(start, end - start) : whole;
  }

  /// Язык главы, чтобы выбрать голос: «ru», «en»… `null` — не понять.
  static String? language(List<SpeechPart> parts) {
    final sample = StringBuffer();
    for (final part in parts) {
      if (part.isHeading || part.spoken == codeNotice) continue;
      sample
        ..write(part.spoken)
        ..write(' ');
      if (sample.length > 2000) break;
    }
    return detectLanguage(sample.toString());
  }

  /// Примерно сколько секунд займут части при обычной скорости: ~15 знаков в секунду.
  static double estimatedSeconds(Iterable<SpeechPart> parts, {double rate = 1}) {
    final characters = parts.fold<int>(0, (sum, p) => sum + p.spoken.length);
    return characters / (15 * (rate < 0.1 ? 0.1 : rate));
  }

  // Разбор

  /// Предложение длиннее предела режется по знакам препинания, а если их нет, по пробелу.
  static List<Span> _cut(String text, Span range) {
    final pieces = <Span>[];
    var start = range.start;
    while (range.end - start > maxPartLength) {
      var limit = start + maxPartLength;
      // Не резать суррогатную пару (эмодзи).
      if (_isLowSurrogate(text.codeUnitAt(limit))) limit--;
      var cut = -1;
      for (var i = limit - 1; i > start; i--) {
        if (',;:—–'.contains(text[i])) {
          cut = i + 1;
          break;
        }
      }
      if (cut < 0) {
        for (var i = limit - 1; i > start; i--) {
          if (_isWhite(text[i])) {
            cut = i;
            break;
          }
        }
      }
      if (cut < 0) cut = limit;
      if (cut <= start) break;
      pieces.add((start: start, end: cut));
      start = cut;
    }
    pieces.add((start: start, end: range.end));
    return pieces;
  }

  /// Склеивает соседние куски, пока часть короче `length` знаков.
  static List<Span> _group(List<Span> pieces, int length) {
    if (length <= 0 || pieces.isEmpty) return pieces;
    final result = <Span>[];
    var current = pieces.first;
    for (final piece in pieces.skip(1)) {
      if (piece.end - current.start <= length) {
        current = (start: current.start, end: piece.end);
      } else {
        result.add(current);
        current = piece;
      }
    }
    result.add(current);
    return result;
  }

  /// Диапазон без пробелов по краям; `null`, если в нём одни пробелы.
  static Span? _trimmed(String text, Span range) {
    var start = range.start;
    var end = range.end;
    while (start < end && _isWhite(text[start])) {
      start++;
    }
    while (end > start && _isWhite(text[end - 1])) {
      end--;
    }
    return start < end ? (start: start, end: end) : null;
  }

  static SpeechPart _part(
    String text,
    String raw,
    int blockStart,
    Span range, {
    required bool isHeading,
  }) {
    final piece = range.end <= raw.length
        ? raw.substring(range.start, range.end)
        : text.substring(range.start, range.end);
    return SpeechPart(
      spoken: clean(piece),
      raw: piece,
      start: blockStart + range.start,
      length: range.end - range.start,
      isHeading: isHeading,
    );
  }

  /// Переводы строк → пробелы, по одному на знак UTF-16: места не сдвигаются.
  static String flattened(String text) => text.replaceAll(_lineBreaks, ' ');

  /// Мягкие переносы, сноски вида [12] и лишние пробелы голосу не нужны.
  static String clean(String text) =>
      text.replaceAll('­', '').replaceAll(_footnote, '').replaceAll(_spaces, ' ').trim();

  /// Номер страницы, «* * *» и прочее, что вслух не читают.
  static bool isNoise(String text) {
    final value = clean(text);
    if (value.isEmpty) return true;
    if (_pageNumber.hasMatch(value)) return true;
    return !hasWords(value);
  }

  static bool hasWords(String text) => _wordChar.hasMatch(text);

  static final _lineBreaks = RegExp('[\n\r\u000B\u000C\u0085  ]');
  static final _footnote = RegExp(r'\[\d{1,3}\]');
  static final _spaces = RegExp(r'\s+');
  static final _pageNumber = RegExp(r'^[\d\s.\-–—]+$');
  static final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _isWhite(String char) => char.trim().isEmpty;
  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}

/// Как склеивать предложения абзаца в части: до `limit` знаков, а с разгоном от места
/// `rampStart` — сначала одно предложение, потом всё длиннее.
final class _Grouping {
  _Grouping({required this.limit, this.rampStart, this.growth = 0});

  final int limit;
  final int? rampStart;
  final double growth;

  /// Длина части, с которой начинается чтение, и сколько знаков прочитано после старта.
  int? _first;
  int _played = 0;

  /// Совсем короткая первая фраза («— Да.») не должна держать разгон на месте.
  static const shortestFirst = 60;

  /// Заголовок или пропущенный код после старта тоже звучит и даёт голосу время.
  void counted(SpeechPart part) {
    if (_first == null) return;
    _played += part.spoken.length;
  }

  List<Span> group(String text, List<Span> pieces, int blockStart) {
    final start = rampStart;
    if (start == null) return SpeechText._group(pieces, limit);
    final result = <Span>[];
    Span? current;
    var currentAfter = false;
    for (final piece in pieces) {
      // Конец без пробелов, как у части: так же считает `indexOf`.
      final last = SpeechText._trimmed(text, piece)?.end ?? piece.end;
      final after = blockStart + last > start;
      if (after && _first == null) {
        // Предложение, с которого начинается чтение: отдельной частью.
        if (current != null) result.add(current);
        final length = piece.end - piece.start;
        _first = length > shortestFirst ? length : shortestFirst;
        _played += length;
        result.add(piece);
        current = null;
        continue;
      }
      final grown = (_first ?? 0) + (growth * _played).floor();
      final budget = after ? (grown < limit ? grown : limit) : limit;
      final joined = current;
      if (joined != null && currentAfter == after && piece.end - joined.start <= budget) {
        current = (start: joined.start, end: piece.end);
        continue;
      }
      if (joined != null) {
        result.add(joined);
        if (currentAfter) _played += joined.end - joined.start;
      }
      current = piece;
      currentAfter = after;
    }
    final done = current;
    if (done != null) {
      result.add(done);
      if (currentAfter) _played += done.end - done.start;
    }
    return result;
  }
}
