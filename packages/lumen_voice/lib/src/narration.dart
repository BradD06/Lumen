import 'package:lumen_core/lumen_core.dart';

import 'language.dart';
import 'phrase_cache.dart';
import 'phrase_queue.dart';
import 'speech_text.dart';
import 'speech_timing.dart';
import 'voice_server.dart';

/// Текст для озвучки: глава книги или любой другой текст. Вход — простой текст и места
/// абзацев в нём (как `Chapter.text` и `Chapter.paragraphs`), плюс `id` для места
/// прослушивания. Своей модели книги у озвучки нет.
final class NarrationText {
  NarrationText({required this.id, required this.text, List<TextRange> paragraphs = const []})
    : blocks = SpeechBlock.paragraphs(text, paragraphs);

  /// Из готовых абзацев: склеиваются через пустую строку, места считаются сами.
  factory NarrationText.fromParagraphs(String id, List<String> paragraphs) {
    final ranges = <TextRange>[];
    final text = StringBuffer();
    for (final paragraph in paragraphs) {
      if (text.isNotEmpty) text.write('\n\n');
      ranges.add(TextRange(text.length, paragraph.length));
      text.write(paragraph);
    }
    return NarrationText(id: id, text: text.toString(), paragraphs: ranges);
  }

  final String id;
  final String text;
  final List<SpeechBlock> blocks;

  /// Предложения: по ним идёт подсветка, и ими читает системный голос.
  late final List<SpeechPart> sentences = SpeechText.parts(blocks);

  /// Язык текста («ru», «en»…), `null` — не понять.
  late final String? language = SpeechText.language(sentences);

  /// Голос сервера знает этот язык; иначе читает системный голос.
  bool get serverVoiceSupports => VoiceLanguages.supports(language);

  /// Части для голоса сервера: с места `offset` одно предложение, дальше абзацы с разгоном.
  List<SpeechPart> serverParts(int offset) => SpeechText.ramped(blocks, startingAt: offset);

  /// Доля прочитанного 0…1 по месту в тексте.
  double progressAt(int offset) {
    if (text.isEmpty) return 0;
    return (offset / text.length).clamp(0.0, 1.0);
  }
}

/// Звучащая часть: её слова со временем и местами в главе. По секунде звука говорит,
/// какое слово и какое предложение подсветить.
final class SpokenPart {
  SpokenPart(this.part, List<SpeechWord>? words, {double? duration})
    : words = words ?? SpeechTiming.estimated(part.spoken, duration ?? _guess(part)),
      places = SpeechTiming.places(part);

  final SpeechPart part;
  final List<SpeechWord> words;
  final List<SpeechWordPlace> places;

  /// Слово в главе, которое звучит на секунде `seconds` фразы (с опережением
  /// `SpeechTiming.wordLead`, иначе подсветка отстаёт от голоса).
  TextRange? wordAt(double seconds) {
    final index = SpeechTiming.indexAt(seconds + SpeechTiming.wordLead, words);
    if (index == null) return null;
    return SpeechTiming.chapterRange(words[index].range, places);
  }

  /// Предложение под звучащим словом (часть может быть целым абзацем).
  TextRange sentenceAt(double seconds, List<SpeechPart> sentences) {
    final word = wordAt(seconds);
    return SpeechText.sentenceAt(word?.start ?? part.start, part, sentences);
  }

  /// Место для сохранения: начало звучащего слова, а нет — начало части.
  int placeAt(double seconds) => wordAt(seconds)?.start ?? part.start;

  static double _guess(SpeechPart part) => SpeechText.estimatedSeconds([part]);
}

/// Место прослушивания. Синхронизация оставляет запись с более поздним временем, поэтому
/// место, на котором текст открыли, заново не пишется: иначе устройство, которое лишь
/// открыло книгу, затёрло бы место, где остановились на другом.
final class PlaceKeeper {
  PlaceKeeper({required this.id, required int openedAt}) : _last = openedAt;

  final String id;
  int _last;

  /// Что записать для места `offset`; `null` — писать нечего, место не сдвинулось.
  int? toSave(int offset) {
    if (offset == _last) return null;
    _last = offset;
    return offset;
  }

  /// Место пришло с другого устройства: оно новое «старое», писать его обратно не нужно.
  void followed(int offset) => _last = offset;
}

/// Очередь для голоса сервера: фразы из кеша, а нет — с сервера.
PhraseQueue serverPhraseQueue({
  required VoiceServer server,
  required PhraseCache cache,
  required String Function() voice,
  required String? language,
  void Function(Object error)? onWaiting,
  void Function(bool loading)? onLoading,
}) => PhraseQueue(
  load: (part) {
    final current = voice();
    return cache.audio(
      server.cacheKey(part.spoken, voice: current, language: language),
      part.spoken,
      () => server.speak(part.spoken, voice: current, language: language),
    );
  },
  onWaiting: onWaiting,
  onLoading: onLoading,
);
