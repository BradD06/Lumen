/// С каким чувством диктор читает строку. Голос у книги один,
/// персонажи различаются только интонацией (решение 26.11.2026).
enum Emotion {
  neutral,
  joy,
  sadness,
  anger,
  fear,
  surprise,
  tenderness,
  irony,
  whisper;

  static Emotion parse(String? name) =>
      Emotion.values.where((e) => e.name == name).firstOrNull ?? Emotion.neutral;
}
