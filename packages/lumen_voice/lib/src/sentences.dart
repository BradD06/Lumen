/// Деление текста на предложения. Места — в кодовых единицах UTF-16 (как индексы строк Dart).
///
/// В Lumen_exemple это делал `NLTokenizer` Apple; здесь свои правила, одинаковые на всех
/// системах. Предложения идут подряд без зазоров: пробелы после точки относятся к предложению,
/// первое забирает и пробелы в начале. Внутри — не больше одного абзаца (текст абзаца приходит
/// без переносов строк, см. `SpeechText.flattened`).
library;

/// Диапазон `[start, end)` в UTF-16.
typedef Span = ({int start, int end});

const _terminators = {'.', '!', '?', '…'};

/// Закрывающие знаки, которые остаются в предложении после точки: «да». или (так!)
const _closers = {'»', '"', '”', '’', "'", ')', ']', '}', '“'};

const _dashes = {'—', '–', '-'};

/// Сокращения, после которых точка — не конец предложения, даже если дальше заглавная
/// (за ними обычно идёт имя: «проф. Иванов», «Dr. Smith»). Сравнение без учёта регистра.
const _abbreviations = {
  // русские
  'т', 'е', 'г', 'гг', 'им', 'ул', 'пр', 'просп', 'пер', 'д', 'кв', 'стр', 'см', 'рис', 'табл',
  'гл', 'ст', 'тыс', 'млн', 'млрд', 'руб', 'коп', 'проф', 'акад', 'доц', 'ген', 'полк', 'кап',
  'тов', 'г-н', 'г-жа', 'св', 'др', 'вв', 'н', 'э', 'напр', 'т.е', 'т.д', 'т.п',
  // английские и общие
  'mr', 'mrs', 'ms', 'dr', 'prof', 'st', 'jr', 'sr', 'vs', 'etc', 'e.g', 'i.e', 'vol',
  'pp', 'fig', 'mt', 'gen', 'col', 'capt', 'lt', 'sgt', 'rev', 'hon', 'inc', 'ltd',
};

bool _isSpace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0D ||
    unit == 0xA0 ||
    unit == 0x202F ||
    unit == 0x2009 ||
    unit == 0x3000;

bool _isLower(String char) => char.toLowerCase() == char && char.toUpperCase() != char;

bool _isLetter(String char) => char.toLowerCase() != char.toUpperCase();

/// Предложения текста. Пустой или пробельный текст — одно «предложение» на весь текст.
List<Span> sentenceSpans(String text) {
  final spans = <Span>[];
  var start = 0;
  var i = 0;
  final n = text.length;
  while (i < n) {
    final char = text[i];
    // Китайская и японская точка и знаки — конец предложения без пробела после них.
    if (char == '。' || char == '！' || char == '？') {
      var end = i + 1;
      while (end < n && _closers.contains(text[end])) {
        end++;
      }
      while (end < n && _isSpace(text.codeUnitAt(end))) {
        end++;
      }
      spans.add((start: start, end: end));
      start = end;
      i = end;
      continue;
    }
    if (!_terminators.contains(char)) {
      i++;
      continue;
    }
    // Серия знаков: «?!», «...», «!..» и закрывающие кавычки и скобки за ней.
    var end = i;
    while (end < n && _terminators.contains(text[end])) {
      end++;
    }
    while (end < n && (_closers.contains(text[end]) || _terminators.contains(text[end]))) {
      end++;
    }
    // Конец предложения только перед пробелом или концом текста: «3.14», «example.com» — нет.
    if (end < n && !_isSpace(text.codeUnitAt(end))) {
      i = end;
      continue;
    }
    var next = end;
    while (next < n && _isSpace(text.codeUnitAt(next))) {
      next++;
    }
    if ((next < n && !_breaksBefore(text, next)) || _isAbbreviation(text, start, i, next)) {
      i = end;
      continue;
    }
    spans.add((start: start, end: next));
    start = next;
    i = next;
  }
  if (start < n || spans.isEmpty) {
    spans.add((start: start, end: n));
  }
  return spans;
}

/// Можно ли начать новое предложение с места `at`: не со строчной буквы.
/// Тире реплики пропускается: «— Да! — сказал он» — одно предложение, «Ушёл. — Куда?» — два.
bool _breaksBefore(String text, int at) {
  var i = at;
  if (_dashes.contains(text[i])) {
    i++;
    while (i < text.length && _isSpace(text.codeUnitAt(i))) {
      i++;
    }
    if (i >= text.length) return true;
  }
  while (i < text.length && _closers.contains(text[i])) {
    i++;
  }
  if (i >= text.length) return true;
  return !_isLower(text[i]);
}

/// Точка в `dot` стоит после сокращения или инициала («А. С. Пушкин», «проф. Иванов», «т. е.»).
bool _isAbbreviation(String text, int sentenceStart, int dot, int next) {
  if (text[dot] != '.') return false;
  // Слово перед точкой (буквы, внутренние точки и дефис: «т.е», «г-н»).
  var from = dot;
  while (from > sentenceStart) {
    final c = text[from - 1];
    if (_isLetter(c) || c == '.' || c == '-') {
      from--;
    } else {
      break;
    }
  }
  final word = text.substring(from, dot);
  if (word.isEmpty) return false;
  // Одна заглавная буква — инициал, если за ней снова заглавная (фамилия или следующий инициал).
  if (word.length == 1 && !_isLower(word) && _isLetter(word)) {
    return next < text.length && _isLetter(text[next]) && !_isLower(text[next]);
  }
  return _abbreviations.contains(word.toLowerCase());
}
