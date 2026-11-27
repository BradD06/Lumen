import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'language.dart';
import 'server_link.dart';
import 'voice_error.dart';

/// Голос, который знает сервер (`GET /v1/voices`).
final class VoiceInfo {
  const VoiceInfo({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is VoiceInfo && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'VoiceInfo($id, $name)';
}

/// Клиент сервера голоса lumen-voice-server (Qwen3-TTS). Сервер отдаёт фразу mp3 или wav,
/// время слов считается по самому звуку (`SpeechAlignment`).
final class VoiceServer {
  VoiceServer(this.link, {http.Client? client, Future<bool> Function()? isOnline})
    : _client = client ?? http.Client(),
      _isOnline = isOnline ?? _probeInternet;

  final ServerLink link;
  final http.Client _client;
  final Future<bool> Function() _isOnline;

  /// Первая фраза может идти долго: сервер прогревается.
  static const speakTimeout = Duration(seconds: 120);
  static const requestTimeout = Duration(seconds: 20);

  Future<List<VoiceInfo>> voices() async {
    final response = await _send(() => _client.get(link.voices, headers: _headers), requestTimeout);
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return const [];
    }
    final list = json is Map ? json['voices'] : null;
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map && item['id'] is String && item['name'] is String)
          VoiceInfo(id: item['id'] as String, name: item['name'] as String),
    ];
  }

  /// Звук одной фразы (mp3 или wav).
  Future<Uint8List> speak(String text, {required String voice, String? language}) async {
    final body = <String, String>{'text': text, 'voice': voice};
    final code = VoiceLanguages.code(language);
    if (code != null) body['language'] = code;
    final response = await _send(
      () => _client.post(
        link.speak,
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
      speakTimeout,
    );
    if (response.bodyBytes.isEmpty) throw const VoiceError(VoiceErrorKind.noSound);
    return response.bodyBytes;
  }

  /// Сервер жив (`/health` без ключа).
  Future<bool> isAlive() async {
    try {
      await _send(() => _client.get(link.health), requestTimeout);
      return true;
    } on VoiceError {
      return false;
    }
  }

  /// Имя файла в кеше: от сервера, голоса, языка и текста. Другой голос — другая озвучка.
  String cacheKey(String text, {required String voice, String? language}) {
    final code = VoiceLanguages.code(language) ?? '';
    final host = link.baseUrl.hasPort
        ? '${link.baseUrl.host}:${link.baseUrl.port}'
        : link.baseUrl.host;
    return sha256.convert(utf8.encode('lumen|$host|$voice|$code|$text')).toString();
  }

  void close() => _client.close();

  Map<String, String> get _headers => {if (link.key != null) 'Authorization': 'Bearer ${link.key}'};

  Future<http.Response> _send(Future<http.Response> Function() request, Duration timeout) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw await _unreachable();
    } on SocketException {
      throw await _unreachable();
    } on http.ClientException {
      throw await _unreachable();
    } on HandshakeException {
      throw const VoiceError(VoiceErrorKind.notResponding);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw parseError(response.statusCode, response.bodyBytes);
    }
    return response;
  }

  /// Не дозвонились: нет сети вообще или молчит сам сервер.
  Future<VoiceError> _unreachable() async {
    final online = await _isOnline().catchError((_) => false);
    return VoiceError(online ? VoiceErrorKind.notResponding : VoiceErrorKind.noInternet);
  }

  static VoiceError parseError(int status, List<int> body) {
    var detail = '';
    try {
      final json = jsonDecode(utf8.decode(body, allowMalformed: true));
      if (json is Map && json['error'] is String) detail = json['error'] as String;
    } on FormatException {
      // Не JSON: текст ошибки не нужен.
    }
    return switch (status) {
      401 || 403 => VoiceError(VoiceErrorKind.wrongKey, status: status, detail: detail),
      502 || 503 || 504 => VoiceError(VoiceErrorKind.starting, status: status, detail: detail),
      _ => VoiceError(VoiceErrorKind.server, status: status, detail: detail),
    };
  }

  /// Есть ли интернет: удаётся ли узнать адрес хотя бы одного общеизвестного сайта.
  /// Ничего о пользователе не отправляется, только DNS-запрос.
  static Future<bool> _probeInternet() async {
    for (final host in const ['one.one.one.one', 'dns.google']) {
      try {
        final found = await InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
        if (found.isNotEmpty) return true;
      } catch (_) {
        // Пробуем следующий.
      }
    }
    return false;
  }
}
