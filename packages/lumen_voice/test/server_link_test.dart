import 'package:lumen_voice/lumen_voice.dart';
import 'package:test/test.dart';

void main() {
  test('ссылка с ключом из окна сервера', () {
    final link = ServerLink.parse(' https://voice.example.ts.net/#key=abc123 ')!;
    expect(link.key, 'abc123');
    expect(link.voices.toString(), 'https://voice.example.ts.net/v1/voices');
    expect(link.speak.toString(), 'https://voice.example.ts.net/v1/speak');
    expect(link.health.toString(), 'https://voice.example.ts.net/health');
  });

  test('адрес без ключа и с путём', () {
    final link = ServerLink.parse('http://10.0.0.5:8000/lumen/')!;
    expect(link.key, isNull);
    expect(link.voices.toString(), 'http://10.0.0.5:8000/lumen/v1/voices');
  });

  test('не адрес', () {
    expect(ServerLink.parse('привет'), isNull);
    expect(ServerLink.parse('ftp://x'), isNull);
    expect(ServerLink.parse(''), isNull);
  });
}
