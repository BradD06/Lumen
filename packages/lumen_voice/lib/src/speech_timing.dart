import 'package:lumen_core/lumen_core.dart';

import 'speech_text.dart';

/// Слово сказанной фразы: где оно в тексте, который получил голос (UTF-16), и с какой
/// секунды звучит.
final class SpeechWord {
  const SpeechWord({required this.location, required this.length, required this.time});

  factory SpeechWord.fromJson(Map<String, Object?> json) => SpeechWord(
    location: json['location']! as int,
    length: json['length']! as int,
    time: (json['time']! as num).toDouble(),
  );

  final int location;
  final int length;
  final double time;

  TextRange get range => TextRange(location, length);

  Map<String, Object?> toJson() => {'location': location, 'length': length, 'time': time};

  @override
  bool operator ==(Object other) =>
      other is SpeechWord &&
      other.location == location &&
      other.length == length &&
      other.time == time;

  @override
  int get hashCode => Object.hash(location, length, time);

  @override
  String toString() => 'SpeechWord($location+$length @$time)';
}

/// Слово фразы и его место в главе: по нему подсвечивается звучащее слово.
final class SpeechWordPlace {
  const SpeechWordPlace({required this.spoken, required this.chapter});

  /// В сказанном тексте (`SpeechPart.spoken`).
  final TextRange spoken;

  /// В главе, как `SpeechPart.start`.
  final TextRange chapter;
}

/// Слова внутри фразы: подсветка идёт за голосом по словам, а не стоит на всей фразе.
abstract final class SpeechTiming {
  /// Подсветка опережает звук: иначе глаз видит, что она отстаёт.
  static const wordLead = 0.12;

  /// Слова текста (буквы и цифры подряд) в UTF-16. Мягкий перенос считается частью слова.
  static List<TextRange> wordRanges(String text) {
    final ranges = <TextRange>[];
    int? start;
    var offset = 0;
    for (final rune in text.runes) {
      final inWord = rune == 0xAD || _isWordRune(rune);
      if (inWord && start == null) start = offset;
      if (!inWord && start != null) {
        ranges.add(TextRange(start, offset - start));
        start = null;
      }
      offset += rune > 0xFFFF ? 2 : 1;
    }
    if (start != null) ranges.add(TextRange(start, offset - start));
    return ranges;
  }

  /// Времени нет (звук не прочитался): слова идут равномерно по длительности фразы.
  static List<SpeechWord> estimated(String text, double duration) {
    final total = text.isEmpty ? 1 : text.length;
    return [
      for (final r in wordRanges(text))
        SpeechWord(location: r.start, length: r.length, time: duration * r.start / total),
    ];
  }

  /// Номер слова, которое звучит на секунде `time`: последнее из начавшихся.
  static int? indexAt(double time, List<SpeechWord> words) {
    var low = 0;
    var high = words.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (words[middle].time <= time) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low > 0) return low - 1;
    return words.isEmpty ? null : 0;
  }

  /// Слова фразы и их места в главе. Сказанный текст — кусок главы без сносок, мягких
  /// переносов и лишних пробелов, поэтому слова сопоставляются по порядку, пропуская лишние
  /// (номер сноски) в главе.
  static List<SpeechWordPlace> places(SpeechPart part) {
    final rawWords = wordRanges(part.raw);
    final places = <SpeechWordPlace>[];
    var next = 0;
    for (final word in wordRanges(part.spoken)) {
      final wanted = _normalized(word.of(part.spoken));
      final last = next + 6 < rawWords.length ? next + 6 : rawWords.length;
      for (var i = next; i < last; i++) {
        if (_normalized(rawWords[i].of(part.raw)) == wanted) {
          final place = rawWords[i];
          places.add(
            SpeechWordPlace(
              spoken: word,
              chapter: TextRange(part.start + place.start, place.length),
            ),
          );
          next = i + 1;
          break;
        }
      }
    }
    return places;
  }

  /// Место в главе для куска сказанного текста (системный голос даёт свои границы слов):
  /// от первого задетого слова до последнего.
  static TextRange? chapterRange(TextRange spoken, List<SpeechWordPlace> places) {
    final end = spoken.start + (spoken.length > 1 ? spoken.length : 1);
    final touched = places.where((p) => p.spoken.start < end && p.spoken.end > spoken.start);
    if (touched.isEmpty) return null;
    final start = touched.first.chapter.start;
    return TextRange(start, touched.last.chapter.end - start);
  }

  static String _normalized(String word) => word.replaceAll('­', '').toLowerCase();

  static final _wordRune = RegExp(r'^[\p{L}\p{N}\p{M}]$', unicode: true);
  static bool _isWordRune(int rune) => _wordRune.hasMatch(String.fromCharCode(rune));
}
