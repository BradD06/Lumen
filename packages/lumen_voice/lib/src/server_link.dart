/// Адрес сервера голоса и ключ из ссылки окна сервера `https://…/#key=…`.
/// Ключ потом кладётся только в защищённое хранилище системы.
final class ServerLink {
  const ServerLink({required this.baseUrl, this.key});

  final Uri baseUrl;
  final String? key;

  /// Разбирает то, что пользователь вставил: ссылку с ключом или просто адрес.
  /// Возвращает `null`, если это не http(s)-адрес.
  static ServerLink? parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
      return null;
    }
    final fragment = Uri.splitQueryString(uri.fragment);
    final key = fragment['key']?.trim();
    final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
    return ServerLink(
      baseUrl: uri.replace(path: path, fragment: null, query: null).removeFragment(),
      key: (key == null || key.isEmpty) ? null : key,
    );
  }

  Uri get voices => _at('/v1/voices');
  Uri get speak => _at('/v1/speak');
  Uri get health => _at('/health');

  Uri _at(String path) => baseUrl.replace(path: '${baseUrl.path}$path');
}
