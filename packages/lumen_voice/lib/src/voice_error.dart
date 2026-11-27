import 'server_state.dart';

/// Что пошло не так с голосом сервера. Текст — для окна в приложении: сервер не всегда стоит
/// у Брэда дома, поэтому нигде не «ПК» и не «компьютер», только «сервер».
enum VoiceErrorKind {
  /// Интернет есть, а сервер не ответил (выключен, закрыт, не та сеть).
  notResponding,

  /// Нет сети вообще.
  noInternet,

  /// Сервер ответил, но ключ не подошёл (401, 403).
  wrongKey,

  /// Сервер ответил, но модель ещё запускается или упала (502, 503, 504).
  starting,

  /// В поле адреса не адрес.
  badAddress,

  /// Ответ пришёл без звука.
  noSound,

  /// Прочая ошибка сервера с его текстом.
  server,
}

final class VoiceError implements Exception {
  const VoiceError(this.kind, {this.status = 0, this.detail = ''});

  final VoiceErrorKind kind;
  final int status;

  /// Текст ошибки от сервера (`{"error": "…"}`), если был.
  final String detail;

  /// Сбой, который проходит сам: сеть моргнула, сервер занят или перезапускается.
  /// Голос ждёт и пробует снова, а не сразу уходит на системный.
  bool get isTemporary => switch (kind) {
    VoiceErrorKind.notResponding || VoiceErrorKind.noInternet || VoiceErrorKind.starting => true,
    _ => false,
  };

  /// Что показать в состоянии связи.
  ServerState get state => switch (kind) {
    VoiceErrorKind.noInternet => ServerState.noInternet,
    VoiceErrorKind.wrongKey => ServerState.wrongKey,
    VoiceErrorKind.badAddress => ServerState.notSet,
    _ => ServerState.notResponding,
  };

  /// Заголовок окна: «Сервер не отвечает», «Нет интернета»…
  String get title => switch (kind) {
    VoiceErrorKind.notResponding => 'Сервер не отвечает',
    VoiceErrorKind.noInternet => 'Нет интернета',
    VoiceErrorKind.wrongKey => 'Ключ не подходит',
    VoiceErrorKind.starting => 'Голос запускается',
    VoiceErrorKind.badAddress => 'Нет адреса сервера',
    VoiceErrorKind.noSound => 'Нет звука',
    VoiceErrorKind.server => 'Ошибка сервера',
  };

  /// Пояснение под заголовком.
  String get message => switch (kind) {
    VoiceErrorKind.notResponding =>
      'Сервер голоса не отвечает. Проверьте, что он запущен и доступен из этой сети.',
    VoiceErrorKind.noInternet =>
      'Нет подключения к интернету. Голос вернётся сам, когда сеть появится.',
    VoiceErrorKind.wrongKey =>
      'Ключ не подходит. Вставьте ссылку с ключом из окна сервера целиком.',
    VoiceErrorKind.starting => 'Голос на сервере ещё запускается, попробуйте через минуту.',
    VoiceErrorKind.badAddress => 'Не вижу адреса сервера. Вставьте ссылку из окна сервера голоса.',
    VoiceErrorKind.noSound => 'Сервер ответил без звука.',
    VoiceErrorKind.server =>
      detail.isEmpty ? 'Ошибка сервера ($status).' : 'Ошибка сервера ($status): $detail',
  };

  @override
  bool operator ==(Object other) =>
      other is VoiceError && other.kind == kind && other.status == status && other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, status, detail);

  @override
  String toString() => 'VoiceError($kind, $status, $detail)';
}
