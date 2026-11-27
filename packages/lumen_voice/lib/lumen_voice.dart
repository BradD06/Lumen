/// Озвучка: сервер голоса, деление текста на фразы, кеш, очередь подгрузки и время слов.
library;

export 'src/language.dart' show VoiceLanguages, detectLanguage;
export 'src/narration.dart';
export 'src/phrase_cache.dart';
export 'src/phrase_queue.dart';
export 'src/server_link.dart';
export 'src/server_settings.dart';
export 'src/server_state.dart';
export 'src/speech_alignment.dart';
export 'src/speech_text.dart';
export 'src/speech_timing.dart';
export 'src/voice_error.dart';
export 'src/voice_server.dart';
