/// Место в тексте главы: начало и длина в кодовых единицах UTF-16,
/// как в строках Dart. Везде считаем одинаково, иначе подсветка уезжает.
final class TextRange {
  const TextRange(this.start, this.length) : assert(start >= 0), assert(length >= 0);

  final int start;
  final int length;

  int get end => start + length;

  bool contains(int offset) => offset >= start && offset < end;

  String of(String text) => text.substring(start, end);

  @override
  bool operator ==(Object other) =>
      other is TextRange && other.start == start && other.length == length;

  @override
  int get hashCode => Object.hash(start, length);

  @override
  String toString() => 'TextRange($start, $length)';
}
