import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app.dart';
import 'package:lumen/narration/audio_outputs.dart';
import 'package:lumen/narration/narration_controller.dart';
import 'package:lumen/narration/prefs.dart';
import 'package:lumen/library/chapter_content.dart';
import 'package:lumen/shell/mini_player.dart';
import 'package:lumen/shell/tabs.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_import/lumen_import.dart';
import 'package:lumen_player/lumen_player.dart';
import 'package:lumen_voice/lumen_voice.dart';
import 'package:lumen_storage/lumen_storage.dart';
import 'package:material_ui/material_ui.dart' hide TextRange;

Future<void> _openChapter(WidgetTester tester) async {
  final store = MemoryBookStore();
  final text = [
    for (var c = 1; c <= 2; c++) ...[
      'Глава $c',
      for (var p = 0; p < 30; p++) 'Абзац $p главы $c. Ночь была тиха, и город спал.',
    ],
  ].join('\n\n');
  await store.save(parsePlainText(text, title: 'Тихая ночь').toBook('b1'));
  await tester.pumpWidget(LumenApp(store: store));
  await tester.tap(find.bySemanticsLabel(AppTab.library.label));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('Тихая ночь'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Глава 1').first);
  await tester.pumpAndSettle();
}

/// Есть ли в тексте подсветка голоса.
bool _highlighted(WidgetTester tester) => tester
    .widgetList<NarrationMarks>(find.byType(NarrationMarks))
    .any((m) => m.word != null || m.sentence != null);

void main() {
  testWidgets('«Слушать» подсвечивает предложение, после выхода из книги — мини-плеер', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openChapter(tester);
    expect(_highlighted(tester), isFalse);

    await tester.tap(find.byTooltip('Слушать  Пробел'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_highlighted(tester), isTrue);
    // Кнопки перемотки работают, когда глава играет.
    await tester.tap(find.byTooltip('Следующая фраза'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Пауза  Пробел'), findsOneWidget);

    // Выходим к списку книг: книга играет дальше, над островом мини-плеер.
    await tester.tap(find.byTooltip('Назад').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад').last);
    await tester.pumpAndSettle();
    expect(find.byType(MiniPlayer).hitTestable(), findsOneWidget);
    expect(find.byTooltip('Пауза'), findsOneWidget);
    await tester.tap(find.byTooltip('Пауза'));
    await tester.pump();
    expect(find.byTooltip('Слушать'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pump();
    expect(find.text('Абзац 0 главы 1. Ночь была тиха, и город спал.'), findsNothing);
    expect(find.byTooltip('Слушать'), findsNothing);
  });

  testWidgets('«Голоса»: не ссылка — понятная ошибка', (tester) async {
    await tester.pumpWidget(const LumenApp());
    await tester.tap(find.bySemanticsLabel(AppTab.voices.label));
    await tester.pumpAndSettle();
    expect(find.text('Сервер голоса'), findsOneWidget);
    expect(find.text('Не подключён'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'просто текст');
    await tester.tap(find.text('Подключить'));
    await tester.pumpAndSettle();
    expect(find.text('Нет адреса сервера'), findsOneWidget);
    expect(find.text('Системный голос'), findsOneWidget);
  });

  test('место экрана текста и место голоса переводятся друг в друга', () {
    final chapter = Chapter.fromParagraphs(
      title: 'Глава',
      paragraphs: ['Первый абзац текста.', 'Второй абзац, подлиннее первого.', 'Третий.'],
      images: [const ChapterImage(position: 1, name: 'a.png')],
    );
    // Пункты экрана: абзац 0, картинка, абзац 1, абзац 2.
    final second = chapter.paragraphs[1];
    final offset = second.start + 7;
    final place = placeOfOffset(chapter, offset)!;
    expect(place.item, 2);
    expect(offsetOfPlace(chapter, place), offset);
    // Место на картинке — голос начинает со следующего абзаца.
    expect(offsetOfPlace(chapter, const ChapterPlace(item: 1, within: .5)), second.start);
    expect(offsetOfPlace(chapter, null), 0);
  });

  testWidgets('озвучка с музыкой и тишиной собирается (на iPhone падала при запуске)', (
    tester,
  ) async {
    final controller = NarrationController(
      player: _NoPlayer(),
      speech: _NoSpeech(),
      music: LoopPlayer(),
      silence: LoopPlayer(),
      keepAwake: true,
    );
    expect(controller.startupError, isNull);
    controller.setSpeed(1.5);
    controller.setMusicVolume(0.4);
    expect(controller.speed, 1.5);
    controller.dispose();
  });

  test('громкость диктора отдельно от музыки и запоминается', () {
    final prefs = MemoryPrefs();
    final player = _NoPlayer();
    final speech = _NoSpeech();
    final controller = NarrationController(player: player, speech: speech, prefs: prefs);
    expect(controller.voiceVolume, 1);
    expect(player.volume, 1);
    controller.setVoiceVolume(0.6);
    controller.setMusicVolume(0.2);
    expect(player.volume, 0.6);
    expect(speech.volume, 0.6);
    expect(controller.mix.musicVolume, 0.2);
    controller.dispose();

    final again = NarrationController(player: _NoPlayer(), speech: _NoSpeech(), prefs: prefs);
    expect(again.voiceVolume, 0.6);
    again.dispose();
  });
}

final class _NoPlayer implements PhrasePlayer, VoiceVolume {
  double volume = -1;
  @override
  Future<void> setVolume(double volume) async => this.volume = volume;
  @override
  Future<bool> play(PhraseAudio audio, {Duration from = Duration.zero, double speed = 1}) async =>
      false;
  @override
  Duration get position => Duration.zero;
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> stop() async {}
}

final class _NoSpeech implements SystemSpeech, VoiceVolume {
  double volume = -1;
  @override
  Future<void> setVolume(double volume) async => this.volume = volume;
  @override
  Future<bool> speak(
    String text, {
    String? language,
    double speed = 1,
    void Function(int start, int end)? onWord,
  }) async => false;
  @override
  Future<void> stop() async {}
}
