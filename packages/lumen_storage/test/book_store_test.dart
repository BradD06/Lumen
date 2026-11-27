import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_storage/lumen_storage.dart';
import 'package:test/test.dart';

void main() {
  test('сохранить, найти, удалить', () async {
    final store = MemoryBookStore();
    final seen = <int>[];
    final sub = store.watchBooks().listen((b) => seen.add(b.length));
    await pumpEventQueue();
    await store.save(const Book(id: '1', title: 'Мёртвые души'));
    expect((await store.book('1'))?.title, 'Мёртвые души');
    await pumpEventQueue();
    await store.delete('1');
    expect(await store.book('1'), isNull);
    await pumpEventQueue();
    expect(seen, [0, 1, 0]);
    await sub.cancel();
  });
}
