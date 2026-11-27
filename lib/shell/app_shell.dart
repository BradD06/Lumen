import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/add_book_screen.dart';
import '../screens/catalog_screen.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/voices_screen.dart';
import '../screens/tab_page.dart';
import '../theme/glass.dart';
import 'island.dart';
import 'profile_button.dart';
import 'tabs.dart';

/// Корень окна: пять разделов и плавающий остров внизу.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _tab = AppTab.home;

  void _select(AppTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  static bool get _apple =>
      defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

  SingleActivator _cmd(LogicalKeyboardKey key) =>
      SingleActivator(key, meta: _apple, control: !_apple);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final top = MediaQuery.paddingOf(context).top + TabPage.windowBar;
    return CallbackShortcuts(
      bindings: {
        // ⌘1…⌘5 — разделы острова, ⌘, — профиль.
        for (final tab in AppTab.values) _cmd(tab.key): () => _select(tab),
        _cmd(LogicalKeyboardKey.keyO): () => _select(AppTab.add),
      },
      child: Focus(
        autofocus: true,
        child: TabSwitcher(
          select: _select,
          child: Scaffold(
            body: GlowBackground(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IndexedStack(
                      index: _tab.index,
                      children: const [
                        HomeScreen(),
                        CatalogScreen(),
                        AddBookScreen(),
                        LibraryScreen(),
                        VoicesScreen(),
                        SettingsScreen(),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 20,
                    top: top + 14,
                    child: ProfileButton(
                      selected: _tab == AppTab.profile,
                      onTap: () => _select(AppTab.profile),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: (bottom > 0 ? bottom : 12) + 12,
                    child: Center(
                      child: NavIsland(selected: _tab, onSelect: _select),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Даёт экранам переключить раздел (например, «Добавить книгу» с главной).
class TabSwitcher extends InheritedWidget {
  const TabSwitcher({super.key, required this.select, required super.child});

  final ValueChanged<AppTab> select;

  static ValueChanged<AppTab> of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TabSwitcher>()!.select;

  @override
  bool updateShouldNotify(TabSwitcher oldWidget) => false;
}
