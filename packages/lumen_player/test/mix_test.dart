import 'package:lumen_player/lumen_player.dart';
import 'package:test/test.dart';

void main() {
  test('музыка выключена — тишина', () {
    expect(const AudioMix().musicLevel(speaking: false), 0);
  });

  test('под голосом музыка тише', () {
    const mix = AudioMix(musicOn: true, musicVolume: 0.4);
    expect(mix.musicLevel(speaking: false), 0.4);
    expect(mix.musicLevel(speaking: true), closeTo(0.2, 1e-9));
    expect(mix.copyWith(duckDuringSpeech: false).musicLevel(speaking: true), 0.4);
  });
}
