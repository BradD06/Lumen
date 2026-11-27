/// Как смешиваются голос и музыка. Музыка — своя дорожка с первого дня,
/// чтобы этап 6 не пришлось встраивать в готовый плеер.
final class AudioMix {
  const AudioMix({
    this.musicOn = false,
    this.musicVolume = 0.3,
    this.duckDuringSpeech = true,
    this.duckLevel = 0.5,
  });

  final bool musicOn;

  /// Громкость музыки 0…1 относительно голоса.
  final double musicVolume;

  /// Приглушать музыку, пока звучит голос.
  final bool duckDuringSpeech;

  /// Во сколько раз тише музыка под голосом.
  final double duckLevel;

  /// Громкость музыки сейчас.
  double musicLevel({required bool speaking}) {
    if (!musicOn) return 0;
    final v = musicVolume.clamp(0.0, 1.0);
    return speaking && duckDuringSpeech ? v * duckLevel.clamp(0.0, 1.0) : v;
  }

  AudioMix copyWith({bool? musicOn, double? musicVolume, bool? duckDuringSpeech}) => AudioMix(
    musicOn: musicOn ?? this.musicOn,
    musicVolume: musicVolume ?? this.musicVolume,
    duckDuringSpeech: duckDuringSpeech ?? this.duckDuringSpeech,
    duckLevel: duckLevel,
  );
}
