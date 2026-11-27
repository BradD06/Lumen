/// Спокойная музыка под голосом диктора. Дорожки синтезирует `tool/make_music.py`
/// (своя музыка, без чужих прав), зацикливаются без шва.
enum MusicTrack {
  evening('evening', 'Тихий вечер', 'Медленные тёплые аккорды'),
  rain('rain', 'Дождь за окном', 'Шум дождя и далёкий гул');

  const MusicTrack(this.id, this.title, this.subtitle);

  final String id;
  final String title;
  final String subtitle;

  String get asset => 'assets/music/$id.mp3';

  static MusicTrack byId(String? id) => values.firstWhere((t) => t.id == id, orElse: () => evening);
}
