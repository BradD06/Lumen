import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen_voice/lumen_voice.dart';
import 'package:test/test.dart';

void main() {
  final link = ServerLink.parse('https://voice.example.ts.net/#key=secret')!;

  test('список голосов с ключом', () async {
    late http.Request seen;
    final server = VoiceServer(
      link,
      client: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'voices': [
              {'id': 'a', 'name': 'Анна'},
              {'id': 'b'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    expect(await server.voices(), const [VoiceInfo(id: 'a', name: 'Анна')]);
    expect(seen.url.toString(), 'https://voice.example.ts.net/v1/voices');
    expect(seen.headers['Authorization'], 'Bearer secret');
  });

  test('звук фразы: текст, голос и язык в запросе', () async {
    late Map<String, dynamic> body;
    final server = VoiceServer(
      link,
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/speak');
        return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'audio/mpeg'});
      }),
    );
    expect(
      await server.speak('Привет.', voice: 'a', language: 'ru-RU'),
      Uint8List.fromList([1, 2, 3]),
    );
    expect(body, {'text': 'Привет.', 'voice': 'a', 'language': 'ru'});
  });

  test('ошибки сервера', () async {
    Future<VoiceError> failWith(int status, [String body = '']) async {
      final server = VoiceServer(
        link,
        client: MockClient((_) async => http.Response.bytes(utf8.encode(body), status)),
      );
      try {
        await server.speak('а', voice: 'a');
      } on VoiceError catch (e) {
        return e;
      }
      fail('ошибки не было');
    }

    expect((await failWith(401)).kind, VoiceErrorKind.wrongKey);
    expect((await failWith(503)).kind, VoiceErrorKind.starting);
    expect((await failWith(503)).isTemporary, isTrue);
    final bad = await failWith(400, '{"error": "Нужен текст"}');
    expect(bad.kind, VoiceErrorKind.server);
    expect(bad.message, 'Ошибка сервера (400): Нужен текст');
    expect((await failWith(200)).kind, VoiceErrorKind.noSound);
  });

  test('«Сервер не отвечает» и «Нет интернета» — разные ошибки', () async {
    Future<VoiceError> unreachable({required bool online}) async {
      final server = VoiceServer(
        link,
        client: MockClient((_) async => throw const SocketException('нет связи')),
        isOnline: () async => online,
      );
      try {
        await server.voices();
      } on VoiceError catch (e) {
        return e;
      }
      fail('ошибки не было');
    }

    final silent = await unreachable(online: true);
    expect(silent.kind, VoiceErrorKind.notResponding);
    expect(silent.title, 'Сервер не отвечает');
    expect(silent.state, ServerState.notResponding);
    final offline = await unreachable(online: false);
    expect(offline.kind, VoiceErrorKind.noInternet);
    expect(offline.title, 'Нет интернета');
    expect(offline.state, ServerState.noInternet);
    // Нигде не «ПК» и не «компьютер».
    for (final kind in VoiceErrorKind.values) {
      final text = '${VoiceError(kind).title} ${VoiceError(kind).message}';
      expect(text, isNot(contains('ПК')));
      expect(text.toLowerCase(), isNot(contains('компьютер')));
    }
  });

  test('ключ кеша зависит от сервера, голоса, языка и текста', () {
    final server = VoiceServer(link);
    final other = VoiceServer(ServerLink.parse('https://other.example/')!);
    final key = server.cacheKey('Привет.', voice: 'a', language: 'ru');
    expect(key, hasLength(64));
    expect(server.cacheKey('Привет.', voice: 'a', language: 'ru-RU'), key);
    expect(server.cacheKey('Привет.', voice: 'b', language: 'ru'), isNot(key));
    expect(server.cacheKey('Привет.', voice: 'a', language: 'en'), isNot(key));
    expect(server.cacheKey('Пока.', voice: 'a', language: 'ru'), isNot(key));
    expect(other.cacheKey('Привет.', voice: 'a', language: 'ru'), isNot(key));
  });

  test('адрес и ключ хранятся только в защищённом хранилище', () async {
    final store = MemorySecretStore();
    final settings = VoiceServerSettings(store);
    expect(await settings.load(), isNull);
    await settings.save(link);
    expect(store.values[VoiceServerSettings.keyName], 'secret');
    expect(store.values[VoiceServerSettings.addressName], isNot(contains('secret')));
    final loaded = (await settings.load())!;
    expect(loaded.key, 'secret');
    expect(loaded.speak.toString(), 'https://voice.example.ts.net/v1/speak');
    await settings.forget();
    expect(store.values, isEmpty);
  });
}
