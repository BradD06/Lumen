import 'dart:convert';

/// Байты файла в текст. Русские TXT и FB2 бывают в UTF-8, UTF-16 и Windows-1251.
///
/// [declared] — кодировка из заголовка XML (`encoding="windows-1251"`), если есть.
String decodeText(List<int> bytes, {String? declared}) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes, 2, little: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes, 2, little: false);
  }
  final name = declared?.toLowerCase().replaceAll('_', '-');
  if (name != null && (name.contains('1251') || name == 'cp-1251')) return decodeCp1251(bytes);
  if (name != null && (name == 'koi8-r')) return _koi8r(bytes);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return decodeCp1251(bytes);
  }
}

/// Кодировка из заголовка XML: `<?xml version="1.0" encoding="windows-1251"?>`.
String? xmlDeclaredEncoding(List<int> bytes) {
  final head = latin1.decode(bytes.take(200).toList(), allowInvalid: true);
  return RegExp(r"""encoding\s*=\s*["']([\w\-]+)["']""").firstMatch(head)?.group(1);
}

String decodeCp1251(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.writeCharCode(b < 0x80 ? b : _cp1251.codeUnitAt(b - 0x80));
  }
  return out.toString();
}

String _utf16(List<int> bytes, int start, {required bool little}) {
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(little ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}

String _koi8r(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.writeCharCode(b < 0x80 ? b : _koi8.codeUnitAt(b - 0x80));
  }
  return out.toString();
}

const _cp1251 =
    '\u0402\u0403\u201A\u0453\u201E\u2026\u2020\u2021\u20AC\u2030\u0409\u2039\u040A\u040C\u040B\u040F'
    '\u0452\u2018\u2019\u201C\u201D\u2022\u2013\u2014\uFFFD\u2122\u0459\u203A\u045A\u045C\u045B\u045F'
    '\u00A0\u040E\u045E\u0408\u00A4\u0490\u00A6\u00A7\u0401\u00A9\u0404\u00AB\u00AC\u00AD\u00AE\u0407'
    '\u00B0\u00B1\u0406\u0456\u0491\u00B5\u00B6\u00B7\u0451\u2116\u0454\u00BB\u0458\u0405\u0455\u0457'
    '\u0410\u0411\u0412\u0413\u0414\u0415\u0416\u0417\u0418\u0419\u041A\u041B\u041C\u041D\u041E\u041F'
    '\u0420\u0421\u0422\u0423\u0424\u0425\u0426\u0427\u0428\u0429\u042A\u042B\u042C\u042D\u042E\u042F'
    '\u0430\u0431\u0432\u0433\u0434\u0435\u0436\u0437\u0438\u0439\u043A\u043B\u043C\u043D\u043E\u043F'
    '\u0440\u0441\u0442\u0443\u0444\u0445\u0446\u0447\u0448\u0449\u044A\u044B\u044C\u044D\u044E\u044F';

const _koi8 =
    '\u2500\u2502\u250C\u2510\u2514\u2518\u251C\u2524\u252C\u2534\u253C\u2580\u2584\u2588\u258C\u2590'
    '\u2591\u2592\u2593\u2320\u25A0\u2219\u221A\u2248\u2264\u2265\u00A0\u2321\u00B0\u00B2\u00B7\u00F7'
    '\u2550\u2551\u2552\u0451\u2553\u2554\u2555\u2556\u2557\u2558\u2559\u255A\u255B\u255C\u255D\u255E'
    '\u255F\u2560\u2561\u0401\u2562\u2563\u2564\u2565\u2566\u2567\u2568\u2569\u256A\u256B\u256C\u00A9'
    '\u044E\u0430\u0431\u0446\u0434\u0435\u0444\u0433\u0445\u0438\u0439\u043A\u043B\u043C\u043D\u043E'
    '\u043F\u044F\u0440\u0441\u0442\u0443\u0436\u0432\u044C\u044B\u0437\u0448\u044D\u0449\u0447\u044A'
    '\u042E\u0410\u0411\u0426\u0414\u0415\u0424\u0413\u0425\u0418\u0419\u041A\u041B\u041C\u041D\u041E'
    '\u041F\u042F\u0420\u0421\u0422\u0423\u0416\u0412\u042C\u042B\u0417\u0428\u042D\u0429\u0427\u042A';
