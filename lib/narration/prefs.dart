import 'package:shared_preferences/shared_preferences.dart';

/// Обычные настройки (скорость, голос, музыка). Ключ сервера сюда никогда не кладётся:
/// он только в защищённом хранилище (`VoiceServerSettings`).
abstract interface class Prefs {
  double? getDouble(String key);
  String? getString(String key);
  bool? getBool(String key);
  void setDouble(String key, double value);
  void setString(String key, String value);
  void setBool(String key, bool value);
}

/// В памяти: тесты.
final class MemoryPrefs implements Prefs {
  final _values = <String, Object>{};

  @override
  double? getDouble(String key) => _values[key] as double?;
  @override
  String? getString(String key) => _values[key] as String?;
  @override
  bool? getBool(String key) => _values[key] as bool?;
  @override
  void setDouble(String key, double value) => _values[key] = value;
  @override
  void setString(String key, String value) => _values[key] = value;
  @override
  void setBool(String key, bool value) => _values[key] = value;
}

/// shared_preferences: настройки системы (NSUserDefaults, SharedPreferences, реестр Windows).
final class SystemPrefs implements Prefs {
  SystemPrefs._(this._prefs);

  static Future<Prefs> open() async {
    try {
      return SystemPrefs._(await SharedPreferences.getInstance());
    } catch (_) {
      return MemoryPrefs();
    }
  }

  final SharedPreferences _prefs;

  @override
  double? getDouble(String key) => _prefs.getDouble(key);
  @override
  String? getString(String key) => _prefs.getString(key);
  @override
  bool? getBool(String key) => _prefs.getBool(key);
  @override
  void setDouble(String key, double value) => _prefs.setDouble(key, value);
  @override
  void setString(String key, String value) => _prefs.setString(key, value);
  @override
  void setBool(String key, bool value) => _prefs.setBool(key, value);
}
