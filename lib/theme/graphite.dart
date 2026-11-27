import 'package:material_ui/material_ui.dart';

/// Цвета «Графита» (docs/DESIGN.md). Интерфейс только чёрный, серый и белый;
/// янтарь — только подсветка слова и прогресс озвучки. Обложки цветные.
abstract final class Graphite {
  static const background = Color(0xFF0C0C11);
  static const text = Color(0xFFF2F2F5);
  static const textMuted = Color(0xFFA5A5B0);
  static const textFaint = Color(0xFF8A8A96);
  static const line = Color(0xFF2A2A32);
  static const track = Color(0xFF3A3A44);

  /// Акцент интерфейса — белый; текст на нём тёмный.
  static const accent = Color(0xFFF2F2F5);
  static const onAccent = Color(0xFF0E0E14);

  /// Янтарь: текущее слово (сплошной фон, тёмный текст), предложение — 16 %.
  static const amber = Color(0xFFF2C166);
  static const onAmber = Color(0xFF1A1408);
  static const amberSoft = Color(0x29F2C166);

  // Стекло.
  static const glassFill = Color(0x13FFFFFF); // .075
  static const glassFillStrong = Color(0x1CFFFFFF); // .11
  static const glassBorder = Color(0x24FFFFFF); // .14
  static const glassHighlight = Color(0x38FFFFFF); // .22
  static const glassShadow = Color(0x47000000); // .28

  // Остров.
  static const islandFill = Color(0x61282838); // rgba(40,40,56,.38)
  static const islandBorder = Color(0x2EFFFFFF); // .18
  static const islandOn = Color(0x29FFFFFF); // .16
  static const islandOffText = Color(0xFF9A9AA6);

  // Мягкие серые свечения фона.
  static const glowA = Color(0xFF4A4A52);
  static const glowB = Color(0xFF6A6A72);
  static const glowC = Color(0xFF3E3E46);

  static const font = 'Onest';

  static ThemeData theme() {
    final base = ThemeData(
      brightness: Brightness.dark,
      fontFamily: font,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: onAccent,
        secondary: accent,
        onSecondary: onAccent,
        surface: background,
        onSurface: text,
        outline: line,
      ),
      // Смена экрана как на Windows на всех системах: новый экран чуть
      // увеличивается и проявляется на месте. Переход Mac и iPhone сдвигал
      // текст вбок (Брэд, 27.11.2026).
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values) platform: ZoomPageTransitionsBuilder(),
        },
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      focusColor: const Color(0x33FFFFFF),
      hoverColor: const Color(0x0FFFFFFF),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: Color(0xF02A2A32),
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        textStyle: TextStyle(fontFamily: font, color: text, fontSize: 12),
        waitDuration: Duration(milliseconds: 400),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text, fontFamily: font),
    );
  }
}
