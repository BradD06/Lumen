import 'package:flutter/services.dart';

/// Пять разделов острова (docs/DESIGN.md). Порядок = ⌘1…⌘5 (на Windows Ctrl).
enum AppTab {
  home(
    'Главная',
    'M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5.5v-6h-5v6H4a1 1 0 0 1-1-1z',
    LogicalKeyboardKey.digit1,
  ),
  library(
    'Библиотека',
    'M5 4h3v16H5zM10.5 4h3v16h-3zM16 5.2l2.9-.8 3 15.4-2.9.8z',
    LogicalKeyboardKey.digit2,
  ),
  add('Добавить', 'M12 5v14M5 12h14', LogicalKeyboardKey.digit3),
  voices(
    'Голоса',
    'M12 3a3 3 0 0 0-3 3v5a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3zM5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21',
    LogicalKeyboardKey.digit4,
  ),
  settings(
    'Профиль',
    'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4.5 20.5a7.5 7.5 0 0 1 15 0',
    LogicalKeyboardKey.digit5,
  );

  const AppTab(this.label, this.iconPath, this.key);

  final String label;

  /// Контур иконки из макета (viewBox 24×24, линия 1.8).
  final String iconPath;
  final LogicalKeyboardKey key;

  String get iconSvg =>
      '<svg viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="1.8" '
      'stroke-linecap="round" stroke-linejoin="round"><path d="$iconPath"/></svg>';
}
