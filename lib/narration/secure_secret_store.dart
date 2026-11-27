import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lumen_voice/lumen_voice.dart';

/// Защищённое хранилище системы для ключа сервера голоса: Связка ключей на Mac и iPhone,
/// Keystore на Android, диспетчер учётных данных на Windows. Никогда не обычные настройки.
final class SecureSecretStore implements SecretStore {
  SecureSecretStore() : _storage = _make();

  final FlutterSecureStorage _storage;

  /// На Mac — обычная Связка ключей, без «Keychain Sharing»: тому нужен профиль подписи,
  /// и приложение запускалось бы только на том Mac, где его собрали.
  static FlutterSecureStorage _make() => Platform.isMacOS
      ? const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false))
      : const FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
        );

  @override
  Future<String?> read(String name) => _storage.read(key: name);

  @override
  Future<void> write(String name, String value) => _storage.write(key: name, value: value);

  @override
  Future<void> delete(String name) => _storage.delete(key: name);
}
