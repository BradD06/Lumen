import 'package:lumen_voice/lumen_voice.dart';
import 'package:test/test.dart';

void main() {
  test('язык текста', () {
    expect(
      detectLanguage('Аграрная революция была одним из самых спорных событий в истории.'),
      'ru',
    );
    expect(
      detectLanguage('The agricultural revolution was one of the most controversial events.'),
      'en',
    );
    expect(detectLanguage('Ще не вмерла України і слава, і воля, ще нам, браття молодії.'), 'uk');
    expect(detectLanguage('Die Katze ist nicht in dem Haus und der Hund schläft.'), 'de');
    expect(detectLanguage("Le chat est dans la maison et il ne veut pas sortir."), 'fr');
    expect(detectLanguage('Nie wiem, jak to jest, ale on był w domu i się śmiał.'), 'pl');
    expect(detectLanguage('今日はいい天気ですね。'), 'ja');
    expect(detectLanguage('今天天气很好。'), 'zh');
    expect(detectLanguage('안녕하세요 반갑습니다'), 'ko');
    expect(detectLanguage('12345 !!!'), isNull);
  });

  test('язык главы по её частям', () {
    final parts = SpeechText.parts([
      const SpeechBlock(
        text: 'The agricultural revolution was one of the most controversial events in history.',
        start: 0,
      ),
    ]);
    expect(SpeechText.language(parts), 'en');
  });

  test('языки, которые знает голос сервера', () {
    expect(VoiceLanguages.supports('ru'), isTrue);
    expect(VoiceLanguages.supports('en-US'), isTrue);
    expect(VoiceLanguages.supports(null), isTrue);
    expect(VoiceLanguages.supports('uk'), isFalse);
    expect(VoiceLanguages.supports('pl'), isFalse);
    expect(VoiceLanguages.code('EN-gb'), 'en');
    expect(VoiceLanguages.code('?'), isNull);
  });

  test('текст на незнакомом языке читает системный голос', () {
    final ukrainian = NarrationText(id: 'b/0', text: 'Ще не вмерла України і слава, і воля.');
    expect(ukrainian.language, 'uk');
    expect(ukrainian.serverVoiceSupports, isFalse);
    expect(NarrationText(id: 'b/1', text: 'Привет, как дела?').serverVoiceSupports, isTrue);
  });
}
