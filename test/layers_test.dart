import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Зависимости между частями только вниз (docs/FEATURES.md, «Как устроен код»):
/// экраны → плеер → озвучка → ядро; хранилище → ядро; разбор книг → ядро.
const allowed = {
  'lumen_core': <String>{},
  'lumen_voice': {'lumen_core'},
  'lumen_storage': {'lumen_core'},
  'lumen_import': {'lumen_core'},
  'lumen_player': {'lumen_core', 'lumen_voice'},
};

void main() {
  for (final entry in allowed.entries) {
    test('${entry.key} зависит только от ${entry.value}', () {
      final pubspec = File('packages/${entry.key}/pubspec.yaml').readAsStringSync();
      final deps = RegExp(
        r'^\s+(lumen_\w+):',
        multiLine: true,
      ).allMatches(pubspec).map((m) => m.group(1)!).toSet();
      expect(deps.difference(entry.value), isEmpty);
    });
  }

  test('ядро не тянет Flutter и чужие пакеты', () {
    final pubspec = File('packages/lumen_core/pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^dependencies:', multiLine: true).hasMatch(pubspec), isFalse);
  });
}
