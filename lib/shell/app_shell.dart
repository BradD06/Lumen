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
import '../theme/fading_glass.dart';
import '../theme/glass.dart';
import 'island.dart';
import 'mini_player.dart';
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

  /// В библиотеке открыта книга или глава: тогда в углу «Назад», а не профиль.
  final _bookOpen = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _bookOpen.dispose();
    super.dispose();
  }

  void _select(AppTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  static bool get _apple =>
      defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

  SingleActivator _cmd(LogicalKeyboardKey key) =>
      SingleActivator(key, meta: _apple, control: !_apple);

  @override
  Widget build(BuildContext context) {
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
          bookOpen: _bookOpen,
          child: Scaffold(
            body: AppBackground(
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
                  // Шапка раздела: стекло под часами и кружком профиля, прокрученный текст
                  // уходит под него и размывается, как под шапкой главы. В открытой книге
                  // у экрана своя шапка.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: top + ProfileButton.top + ProfileButton.size / 2 + 30,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _bookOpen,
                      builder: (context, bookOpen, glass) =>
                          Visibility(visible: !(bookOpen && _tab == AppTab.library), child: glass!),
                      child: const FadingGlass(fadeEdge: AxisDirection.down),
                    ),
                  ),
                  // Профиль — только в разделах; в открытой книге на его месте «Назад»
                  // (Брэд, 27.11.2026).
                  Positioned(
                    left: ProfileButton.left,
                    top: top + ProfileButton.top,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _bookOpen,
                      builder: (context, bookOpen, button) {
                        final hidden = bookOpen && _tab == AppTab.library;
                        return IgnorePointer(
                          ignoring: hidden,
                          child: ExcludeSemantics(
                            excluding: hidden,
                            child: AnimatedOpacity(
                              opacity: hidden ? 0 : 1,
                              duration: const Duration(milliseconds: 160),
                              child: button,
                            ),
                          ),
                        );
                      },
                      child: ProfileButton(
                        selected: _tab == AppTab.profile,
                        onTap: () => _select(AppTab.profile),
                      ),
                    ),
                  ),
                  // Мини-плеер над островом, пока книга играет (в книге его место — плеер).
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: islandClearance(context) + MiniPlayer.gap,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _bookOpen,
                      builder: (context, bookOpen, player) {
                        final hidden = bookOpen && _tab == AppTab.library;
                        return IgnorePointer(
                          ignoring: hidden,
                          child: ExcludeSemantics(
                            excluding: hidden,
                            child: AnimatedOpacity(
                              opacity: hidden ? 0 : 1,
                              duration: const Duration(milliseconds: 200),
                              child: player,
                            ),
                          ),
                        );
                      },
                      child: const Center(child: MiniPlayer()),
                    ),
                  ),
                  // В открытой книге остров уезжает вниз, его место занимает плеер
                  // (Брэд, 27.11.2026).
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: islandBottom(context),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _bookOpen,
                      builder: (context, bookOpen, island) {
                        final hidden = bookOpen && _tab == AppTab.library;
                        return IgnorePointer(
                          ignoring: hidden,
                          child: ExcludeSemantics(
                            excluding: hidden,
                            child: AnimatedSlide(
                              offset: hidden ? const Offset(0, 1.6) : Offset.zero,
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              child: AnimatedOpacity(
                                opacity: hidden ? 0 : 1,
                                duration: const Duration(milliseconds: 200),
                                child: island,
                              ),
                            ),
                          ),
                        );
                      },
                      child: Center(
                        child: NavIsland(selected: _tab, onSelect: _select),
                      ),
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

/// Отступ острова от низа окна.
double islandBottom(BuildContext context) {
  final bottom = MediaQuery.paddingOf(context).bottom;
  return (bottom > 0 ? bottom : 12) + 12;
}

/// Сколько места снизу занимает остров вместе с кружком над ним:
/// панели экрана (прогресс, плеер) ставятся выше.
double islandClearance(BuildContext context) =>
    islandBottom(context) + IslandMetrics.height + IslandMetrics.lift;

/// Даёт экранам переключить раздел (например, «Добавить книгу» с главной)
/// и сказать окну, что в библиотеке открыта книга.
class TabSwitcher extends InheritedWidget {
  const TabSwitcher({
    super.key,
    required this.select,
    required this.bookOpen,
    required super.child,
  });

  final ValueChanged<AppTab> select;

  /// `true`, пока в библиотеке открыта карточка книги или текст главы.
  final ValueNotifier<bool> bookOpen;

  static ValueChanged<AppTab> of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TabSwitcher>()!.select;

  static ValueNotifier<bool>? bookOpenOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TabSwitcher>()?.bookOpen;

  @override
  bool updateShouldNotify(TabSwitcher oldWidget) => false;
}
