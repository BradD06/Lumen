import 'server_link.dart';

/// Защищённое хранилище системы (Связка ключей на Mac и iPhone, Keystore на Android,
/// диспетчер учётных данных на Windows). Само хранилище — в приложении
/// (`lib/narration/secure_secret_store.dart`), здесь только то, что ему нужно уметь.
abstract interface class SecretStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}

/// Хранилище в памяти: для тестов и пока приложение не запущено на устройстве.
final class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String name) async => values[name];

  @override
  Future<void> write(String name, String value) async => values[name] = value;

  @override
  Future<void> delete(String name) async => values.remove(name);
}

/// Адрес и ключ сервера голоса. Ключ лежит только в защищённом хранилище, никогда в обычных
/// настройках или в репозитории; адрес — там же, чтобы они не разошлись.
final class VoiceServerSettings {
  const VoiceServerSettings(this.store);

  final SecretStore store;

  static const addressName = 'voice.server.address';
  static const keyName = 'voice.server.key';

  /// Сохранённый сервер; `null`, если его ещё не задали.
  Future<ServerLink?> load() async {
    final address = await store.read(addressName);
    if (address == null) return null;
    final link = ServerLink.parse(address);
    if (link == null) return null;
    return ServerLink(baseUrl: link.baseUrl, key: await store.read(keyName));
  }

  Future<void> save(ServerLink link) async {
    await store.write(addressName, link.baseUrl.toString());
    final key = link.key;
    if (key == null) {
      await store.delete(keyName);
    } else {
      await store.write(keyName, key);
    }
  }

  Future<void> forget() async {
    await store.delete(addressName);
    await store.delete(keyName);
  }
}
