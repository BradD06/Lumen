import 'dart:math' as math;
import 'dart:typed_data';

import 'speech_timing.dart';

/// Время слов по самому звуку: сервер голоса его не присылает. Тишина в начале и в конце
/// отбрасывается, паузы в речи привязываются к знакам препинания, а между ними слова идут
/// по длине.
abstract final class SpeechAlignment {
  /// Шаг громкости, секунд.
  static const step = 0.01;

  /// Пауза короче этого — просто стык слов.
  static const minimumPause = 0.12;

  static const _breakMarks = {',', '.', ';', ':', '!', '?', '—', '–', '…', '(', ')', '«', '»', '"'};

  /// Слова фразы по звуку; `null`, если громкость не достать (mp3 без декодера) или звук пустой.
  /// mp3 разбирает плеер (этап 3) и передаёт громкость сюда через `wordsFromLevels`.
  static List<SpeechWord>? words(String text, Uint8List audio) {
    final levels = AudioLevels.ofWav(audio);
    if (levels == null || levels.isEmpty) return null;
    final words = wordsFromLevels(text, levels, step: step);
    return words.isEmpty ? null : words;
  }

  /// Слова по громкости звука (`levels` — по `step` секунд). Чистая функция.
  static List<SpeechWord> wordsFromLevels(String text, List<double> levels, {double step = step}) {
    final ranges = SpeechTiming.wordRanges(text);
    if (ranges.isEmpty || levels.isEmpty) return const [];
    final loudest = levels.reduce(math.max);
    if (loudest <= 0) return const [];
    final threshold = loudest * 0.1;
    final first = levels.indexWhere((l) => l >= threshold);
    final last = levels.lastIndexWhere((l) => l >= threshold);
    if (first < 0 || last <= first) return const [];
    final speechStart = first * step;
    final speechEnd = (last + 1) * step;

    // Паузы внутри речи.
    final pauses = <({double start, double end})>[];
    int? quietFrom;
    for (var i = first; i <= last; i++) {
      if (levels[i] < threshold) {
        quietFrom ??= i;
      } else if (quietFrom != null) {
        if ((i - quietFrom) * step >= minimumPause - 1e-9) {
          pauses.add((start: quietFrom * step, end: i * step));
        }
        quietFrom = null;
      }
    }

    // Места между словами, где стоит знак препинания: там голос делает паузу.
    final breaks = <({int before, int after})>[];
    for (var i = 0; i + 1 < ranges.length; i++) {
      final gapStart = ranges[i].end;
      final gap = text.substring(gapStart, ranges[i + 1].start);
      if (gap.split('').any(_breakMarks.contains)) {
        breaks.add((before: gapStart, after: ranges[i + 1].start));
      }
    }

    // Пауза → ближайший по ожидаемому месту знак, по порядку.
    final total = text.length.toDouble();
    final pausing = pauses.fold<double>(0, (sum, p) => sum + p.end - p.start);
    final speaking = math.max(speechEnd - speechStart - pausing, step);
    final anchors = <({double position, double time})>[(position: 0, time: speechStart)];
    var pausedBefore = 0.0;
    var nextBreak = 0;
    for (final pause in pauses) {
      final expected = (pause.start - speechStart - pausedBefore) / speaking * total;
      pausedBefore += pause.end - pause.start;
      int? best;
      for (var i = nextBreak; i < breaks.length; i++) {
        if (best == null ||
            (breaks[i].before - expected).abs() < (breaks[best].before - expected).abs()) {
          best = i;
        }
      }
      if (best == null || (breaks[best].before - expected).abs() > math.max(12, total * 0.2)) {
        continue;
      }
      anchors.add((position: breaks[best].before.toDouble(), time: pause.start));
      anchors.add((position: breaks[best].after.toDouble(), time: pause.end));
      nextBreak = best + 1;
    }
    anchors.add((position: total, time: speechEnd));

    return [
      for (final r in ranges)
        SpeechWord(location: r.start, length: r.length, time: _time(r.start.toDouble(), anchors)),
    ];
  }

  /// Время для места в тексте: прямая между соседними опорами.
  static double _time(double position, List<({double position, double time})> anchors) {
    final upper = anchors.indexWhere((a) => a.position > position);
    if (upper <= 0) return anchors.last.time;
    final a = anchors[upper - 1];
    final b = anchors[upper];
    final share = b.position > a.position ? (position - a.position) / (b.position - a.position) : 0;
    return a.time + (b.time - a.time) * share;
  }
}

/// Громкость и длительность звука фразы без системных декодеров.
abstract final class AudioLevels {
  static bool isWave(Uint8List data) =>
      data.length >= 12 &&
      data[0] == 0x52 && // R
      data[1] == 0x49 && // I
      data[2] == 0x46 && // F
      data[3] == 0x46; // F

  /// Громкость wav по `step` секунд (среднеквадратичная, первый канал). PCM 8/16/24/32 бит
  /// и float32. `null`, если это не wav или формат незнакомый.
  static List<double>? ofWav(Uint8List data, {double step = SpeechAlignment.step}) {
    final wav = _Wave.parse(data);
    if (wav == null) return null;
    final window = math.max((wav.sampleRate * step).round(), 1);
    final levels = <double>[];
    var sum = 0.0;
    var count = 0;
    for (var frame = 0; frame < wav.frames; frame++) {
      final s = wav.sample(frame);
      sum += s * s;
      count++;
      if (count == window) {
        levels.add(math.sqrt(sum / count));
        sum = 0;
        count = 0;
      }
    }
    if (count > 0) levels.add(math.sqrt(sum / count));
    return levels;
  }

  /// Длительность фразы в секундах: wav по заголовку, mp3 по кадрам. `null` — не понять.
  static double? duration(Uint8List data) {
    final wav = _Wave.parse(data);
    if (wav != null) return wav.frames / wav.sampleRate;
    return _mp3Duration(data);
  }

  /// Длительность mp3: сумма кадров MPEG-1/2/2.5 Layer III.
  static double? _mp3Duration(Uint8List data) {
    var i = 0;
    // Тег ID3v2 в начале.
    if (data.length > 10 && data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) {
      final size = (data[6] << 21) | (data[7] << 14) | (data[8] << 7) | data[9];
      i = 10 + size;
    }
    var seconds = 0.0;
    var frames = 0;
    while (i + 4 <= data.length) {
      if (data[i] != 0xFF || (data[i + 1] & 0xE0) != 0xE0) {
        i++;
        continue;
      }
      final version = (data[i + 1] >> 3) & 0x03; // 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5
      final layer = (data[i + 1] >> 1) & 0x03; // 1 = Layer III
      final bitrateIndex = (data[i + 2] >> 4) & 0x0F;
      final rateIndex = (data[i + 2] >> 2) & 0x03;
      final padding = (data[i + 2] >> 1) & 0x01;
      if (version == 1 || layer != 1 || bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3) {
        i++;
        continue;
      }
      final mpeg1 = version == 3;
      final bitrate = (mpeg1 ? _bitrates1 : _bitrates2)[bitrateIndex] * 1000;
      final sampleRate = _sampleRates[rateIndex] ~/ (mpeg1 ? 1 : (version == 2 ? 2 : 4));
      final samples = mpeg1 ? 1152 : 576;
      final length = (samples ~/ 8) * bitrate ~/ sampleRate + padding;
      if (length <= 4) {
        i++;
        continue;
      }
      seconds += samples / sampleRate;
      frames++;
      i += length;
    }
    return frames == 0 ? null : seconds;
  }

  static const _bitrates1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
  static const _bitrates2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
  static const _sampleRates = [44100, 48000, 32000];
}

/// Заголовок wav и доступ к сэмплам первого канала (−1…1).
final class _Wave {
  _Wave(
    this._data,
    this._offset,
    this.frames,
    this.sampleRate,
    this._channels,
    this._bits,
    this._float,
  );

  final ByteData _data;
  final int _offset;
  final int frames;
  final int sampleRate;
  final int _channels;
  final int _bits;
  final bool _float;

  static _Wave? parse(Uint8List bytes) {
    if (!AudioLevels.isWave(bytes)) return null;
    final data = ByteData.sublistView(bytes);
    int? format, channels, sampleRate, bits;
    var i = 12;
    while (i + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes, i, i + 4);
      var size = data.getUint32(i + 4, Endian.little);
      final body = i + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
        // WAVE_FORMAT_EXTENSIBLE: настоящий формат в подзаголовке.
        if (format == 0xFFFE && body + 26 <= bytes.length) {
          format = data.getUint16(body + 24, Endian.little);
        }
      } else if (id == 'data') {
        if (format == null || channels == null || sampleRate == null || bits == null) return null;
        if (channels == 0 || sampleRate == 0) return null;
        final isFloat = format == 3 && bits == 32;
        if (!isFloat && (format != 1 || ![8, 16, 24, 32].contains(bits))) return null;
        // Сервер, который пишет звук потоком, ставит размер 0 или 0xFFFFFFFF.
        if (size == 0 || body + size > bytes.length) size = bytes.length - body;
        final frameSize = channels * bits ~/ 8;
        return _Wave(data, body, size ~/ frameSize, sampleRate, channels, bits, isFloat);
      }
      i = body + size + (size.isOdd ? 1 : 0);
    }
    return null;
  }

  double sample(int frame) {
    final at = _offset + frame * _channels * _bits ~/ 8;
    if (_float) return _data.getFloat32(at, Endian.little);
    switch (_bits) {
      case 8:
        return (_data.getUint8(at) - 128) / 128;
      case 16:
        return _data.getInt16(at, Endian.little) / 32768;
      case 24:
        var v = _data.getUint8(at) | (_data.getUint8(at + 1) << 8) | (_data.getUint8(at + 2) << 16);
        if (v & 0x800000 != 0) v -= 0x1000000;
        return v / 8388608;
      default:
        return _data.getInt32(at, Endian.little) / 2147483648;
    }
  }
}
