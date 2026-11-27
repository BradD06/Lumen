/// Язык текста по буквам и частым словам: «ru», «en», «uk»… `null` — не понять.
///
/// В Lumen_exemple это делал `NLLanguageRecognizer` Apple. Здесь хватает простого: голосу
/// нужно лишь решить, знает ли он язык книги (`VoiceLanguages.supports`), а книги длинные.
String? detectLanguage(String text) {
  var cyrillic = 0, latin = 0, han = 0, kana = 0, hangul = 0, greek = 0, arabic = 0, hebrew = 0;
  for (final rune in text.runes) {
    if (rune >= 0x0400 && rune <= 0x04FF) {
      cyrillic++;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0xC0 && rune <= 0x24F)) {
      latin++;
    } else if (rune >= 0x3040 && rune <= 0x30FF) {
      kana++;
    } else if (rune >= 0x4E00 && rune <= 0x9FFF) {
      han++;
    } else if (rune >= 0xAC00 && rune <= 0xD7AF) {
      hangul++;
    } else if (rune >= 0x0370 && rune <= 0x03FF) {
      greek++;
    } else if (rune >= 0x0600 && rune <= 0x06FF) {
      arabic++;
    } else if (rune >= 0x0590 && rune <= 0x05FF) {
      hebrew++;
    }
  }
  final counts = {
    'cyrillic': cyrillic,
    'latin': latin,
    'cjk': han + kana,
    'ko': hangul,
    'el': greek,
    'ar': arabic,
    'he': hebrew,
  };
  final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
  if (top.value == 0) return null;
  switch (top.key) {
    case 'cyrillic':
      return _cyrillic(text.toLowerCase());
    case 'latin':
      return _latin(text.toLowerCase());
    case 'cjk':
      return kana > 0 ? 'ja' : 'zh';
    default:
      return top.key;
  }
}

/// Русский, украинский, белорусский или сербский — по своим буквам.
String _cyrillic(String text) {
  int count(String letters) => text.runes.where((r) => letters.runes.contains(r)).length;
  final total = text.runes.where((r) => r >= 0x0400 && r <= 0x04FF).length;
  final share = total == 0 ? 0.0 : 1.0 / total;
  if (count('ўі') * share > 0.01 && count('ў') > 0) return 'be';
  if (count('їєґі') * share > 0.01) return 'uk';
  if (count('ђћљњџј') * share > 0.005) return 'sr';
  return 'ru';
}

/// Латиница: частые короткие слова каждого языка.
String _latin(String text) {
  final words = text.split(RegExp(r'[^\p{L}]+', unicode: true)).where((w) => w.isNotEmpty);
  final scores = {for (final language in _stopwords.keys) language: 0};
  for (final word in words) {
    for (final entry in _stopwords.entries) {
      if (entry.value.contains(word)) scores[entry.key] = scores[entry.key]! + 1;
    }
  }
  final best = scores.entries.reduce((a, b) => b.value > a.value ? b : a);
  // Слов не нашлось — скорее всего английский (названия, имена).
  return best.value == 0 ? 'en' : best.key;
}

const _stopwords = {
  'en': {
    'the',
    'and',
    'of',
    'to',
    'is',
    'was',
    'in',
    'that',
    'it',
    'he',
    'she',
    'with',
    'for',
    'you',
  },
  'de': {
    'der',
    'die',
    'und',
    'das',
    'ist',
    'nicht',
    'ich',
    'sie',
    'mit',
    'ein',
    'eine',
    'zu',
    'den',
  },
  'fr': {
    'le',
    'la',
    'les',
    'et',
    'est',
    'un',
    'une',
    'des',
    'du',
    'que',
    'pas',
    'il',
    'elle',
    'je',
  },
  'es': {'el', 'los', 'las', 'y', 'es', 'que', 'una', 'por', 'con', 'del', 'para', 'pero', 'no'},
  'it': {'il', 'gli', 'e', 'che', 'di', 'una', 'non', 'per', 'con', 'sono', 'della', 'anche'},
  'pt': {'o', 'os', 'as', 'e', 'que', 'uma', 'não', 'com', 'para', 'do', 'da', 'por', 'mas'},
  'pl': {'i', 'w', 'nie', 'się', 'na', 'jest', 'że', 'to', 'z', 'jak', 'ale', 'jego', 'był'},
  'nl': {'de', 'het', 'een', 'en', 'van', 'niet', 'ik', 'dat', 'is', 'zijn', 'met', 'op'},
};

/// Языки, которые читает голос сервера (Qwen3-TTS). Остальные книги читает системный голос.
abstract final class VoiceLanguages {
  static const supported = {'ru', 'en', 'de', 'fr', 'es', 'it', 'pt', 'zh', 'ja', 'ko'};

  /// Язык книги по силам голосу сервера; неизвестный язык считается русским.
  static bool supports(String? language) {
    if (language == null || language.length < 2) return true;
    return supported.contains(language.substring(0, 2).toLowerCase());
  }

  /// Код для запроса к серверу: две буквы или `null`.
  static String? code(String? language) {
    if (language == null || language.length < 2) return null;
    final code = language.substring(0, 2).toLowerCase();
    return RegExp(r'^[a-z]{2}$').hasMatch(code) ? code : null;
  }
}
