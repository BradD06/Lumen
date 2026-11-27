import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'speech_alignment.dart';
import 'speech_timing.dart';

/// Звук одной фразы и время её слов (`null` — не посчиталось, плеер разложит слова
/// равномерно по длительности, `SpeechTiming.estimated`).
final class PhraseAudio {
  const PhraseAudio({required this.data, this.words});

  final Uint8List data;
  final List<SpeechWord>? words;

  bool get isWave => AudioLevels.isWave(data);

  /// Расширение файла: сервер присылает mp3 или wav.
  String get extension => isWave ? 'wav' : 'mp3';

  /// Длительность в секундах, если её видно по самому файлу.
  double? get duration => AudioLevels.duration(data);
}

/// Время слов по звуку. По умолчанию — только для wav (`SpeechAlignment.words`);
/// плеер может подставить свой разбор mp3.
typedef WordAligner = List<SpeechWord>? Function(String text, Uint8List audio);

/// Озвученные фразы на устройстве: второй раз та же фраза не просится у сервера.
/// Файлы `<ключ>.mp3` (или `.wav`) и `<ключ>.words.json` в одной папке.
/// Старые файлы удаляются, когда кеш перерастает `limit`.
final class PhraseCache {
  PhraseCache(this.directory, {this.limit = defaultLimit, WordAligner? align})
    : _align = align ?? SpeechAlignment.words;

  static const defaultLimit = 400 * 1024 * 1024;

  final Directory directory;
  final int limit;
  final WordAligner _align;

  /// Одна загрузка на фразу: две просьбы одного и того же ждут один ответ.
  final _inFlight = <String, Future<PhraseAudio>>{};
  var _writesSinceTrim = 0;

  /// Фраза из кеша или из `fetch`. Загрузка не отменяется вместе с тем, кто её попросил
  /// (пауза, переход, смена главы): звук всегда дописывается в кеш.
  Future<PhraseAudio> audio(String key, String text, Future<Uint8List> Function() fetch) {
    final running = _inFlight[key];
    if (running != null) return running;
    // Скобки, а не `=>`: `remove` вернул бы саму загрузку, и она ждала бы себя.
    final future = _load(key, text, fetch).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  Future<PhraseAudio> _load(String key, String text, Future<Uint8List> Function() fetch) async {
    final cached = await read(key, text);
    if (cached != null) return cached;
    final data = await fetch();
    final audio = PhraseAudio(data: data, words: _align(text, data));
    await write(key, audio);
    return audio;
  }

  /// Фраза уже лежит в кеше.
  Future<bool> has(String key) async {
    for (final ext in const ['mp3', 'wav']) {
      if (await _file(key, ext).exists()) return true;
    }
    return false;
  }

  /// Фраза из кеша; `null`, если её нет. Без времени слов оно один раз считается по звуку.
  Future<PhraseAudio?> read(String key, String text) async {
    for (final ext in const ['mp3', 'wav']) {
      final file = _file(key, ext);
      if (!await file.exists()) continue;
      final data = await file.readAsBytes();
      if (data.isEmpty) continue;
      _touch(file);
      final wordsFile = _wordsFile(key);
      List<SpeechWord>? words;
      if (await wordsFile.exists()) {
        words = _decodeWords(await wordsFile.readAsString());
        _touch(wordsFile);
      }
      if (words == null) {
        words = _align(text, data);
        await _saveWords(key, words);
      }
      return PhraseAudio(data: data, words: words);
    }
    return null;
  }

  Future<void> write(String key, PhraseAudio audio) async {
    await directory.create(recursive: true);
    final file = _file(key, audio.extension);
    final temp = File('${file.path}.part');
    await temp.writeAsBytes(audio.data, flush: true);
    await temp.rename(file.path);
    await _saveWords(key, audio.words);
    if (++_writesSinceTrim >= 20) {
      _writesSinceTrim = 0;
      await trim();
    }
  }

  /// Сколько байт занимает кеш (для строки «Кеш голоса: 120 МБ» в настройках).
  Future<int> size() async {
    var total = 0;
    for (final file in await _files()) {
      total += await file.length();
    }
    return total;
  }

  /// «Очистить кеш»: после обновления сервера голоса фразы могут звучать иначе.
  Future<void> clear() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  /// Удаляет самые давние файлы, пока кеш больше `limit`.
  Future<void> trim() async {
    final files = await _files();
    final stats = <(File, FileStat)>[for (final f in files) (f, await f.stat())];
    var total = stats.fold<int>(0, (sum, s) => sum + s.$2.size);
    if (total <= limit) return;
    stats.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in stats) {
      if (total <= limit * 0.9) break;
      try {
        await file.delete();
        total -= stat.size;
      } on FileSystemException {
        // Файл уже удалили.
      }
    }
  }

  Future<List<File>> _files() async {
    if (!await directory.exists()) return const [];
    return [
      await for (final e in directory.list())
        if (e is File) e,
    ];
  }

  File _file(String key, String ext) => File('${directory.path}/$key.$ext');
  File _wordsFile(String key) => File('${directory.path}/$key.words.json');

  Future<void> _saveWords(String key, List<SpeechWord>? words) async {
    if (words == null) return;
    await directory.create(recursive: true);
    await _wordsFile(key).writeAsString(jsonEncode([for (final w in words) w.toJson()]));
  }

  static List<SpeechWord>? _decodeWords(String json) {
    try {
      final list = jsonDecode(json) as List;
      return [for (final item in list) SpeechWord.fromJson((item as Map).cast<String, Object?>())];
    } catch (_) {
      return null;
    }
  }

  /// Свежая дата: давно не звучавшие фразы удаляются первыми.
  static void _touch(File file) {
    try {
      file.setLastModifiedSync(DateTime.now());
    } on FileSystemException {
      // Не страшно: удалится чуть раньше.
    }
  }
}
