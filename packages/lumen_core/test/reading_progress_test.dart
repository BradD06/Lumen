import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  test('доля книги: главы до текущей прочитаны, текущая — по месту', () {
    const lengths = [100, 300, 600];
    expect(ReadingProgress.empty.ofBook(lengths), 0);
    final p = ReadingProgress.empty.withChapter(0, 1).withChapter(1, 0.5);
    expect(p.current, 1);
    expect(p.ofBook(lengths), closeTo((100 + 150) / 1000, 1e-9));
    expect(p.finished(0), isTrue);
    expect(p.finished(1), isFalse);
    expect(p.of(2), 0);
    expect(p.withChapter(2, 1).ofBook(lengths), 1);
  });
}
