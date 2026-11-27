import 'dart:io';
import 'dart:ui';

import 'package:lumen_core/lumen_core.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/glass.dart';
import 'book_cover.dart';

/// Переходы книги (Брэд, 27.11.2026; заменяют «зум как на Windows» для книги):
/// без наложения двух экранов друг на друга и без рывков.
///
/// Книга: экран за обложкой размывается, обложка вырастает до ~85 % экрана
/// по центру, потом встаёт на своё место в карточке, и проявляется список глав.
/// Глава: экран размывается, затем проявляется текст. Пока экран размыт,
/// книга и текст готовятся (книга читается в фоне, текст раскладывается
/// невидимым), поэтому появляются уже готовыми.

/// Метка обложки для перелёта из библиотеки в карточку книги.
Object coverHeroTag(String bookId) => 'cover:$bookId';

/// Обложка, которая летит из библиотеки в карточку книги через центр экрана.
class FlyingCover extends StatelessWidget {
  const FlyingCover({super.key, required this.book, required this.child});

  final Book book;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Hero(
      tag: coverHeroTag(book.id),
      createRectTween: (begin, end) =>
          _ViaCenterRectTween(begin: begin, end: end, middle: bigCoverRect(screen)),
      flightShuttleBuilder: (_, _, _, _, _) => _BigCover(book: book),
      child: child,
    );
  }
}

/// Обложка посреди экрана: ~85 % высоты, но не шире 85 % ширины.
Rect bigCoverRect(Size screen) {
  var height = screen.height * .85;
  var width = height * 2 / 3;
  if (width > screen.width * .85) {
    width = screen.width * .85;
    height = width * 3 / 2;
  }
  return Rect.fromCenter(center: screen.center(Offset.zero), width: width, height: height);
}

/// Путь обложки: к центру и до большого размера, короткая пауза, потом на место.
class _ViaCenterRectTween extends RectTween {
  _ViaCenterRectTween({super.begin, super.end, required this.middle});

  final Rect middle;

  static const _grown = .5;
  static const _hold = .6;

  @override
  Rect? lerp(double t) {
    if (t <= _grown) {
      return Rect.lerp(begin, middle, Curves.easeInOutCubic.transform(t / _grown));
    }
    if (t <= _hold) return middle;
    return Rect.lerp(middle, end, Curves.easeInOutCubic.transform((t - _hold) / (1 - _hold)));
  }
}

/// Обложка в полёте: рисованная масштабируется целиком, картинка — в высоком
/// разрешении поверх уже готовой маленькой (пока большая грузится, видна она).
class _BigCover extends StatelessWidget {
  const _BigCover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final small = FittedBox(
      child: SizedBox(
        width: 120,
        height: 180,
        child: BookCover(book: book, radius: 10, titleSize: 13),
      ),
    );
    final path = book.coverPath;
    if (path == null) return small;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: [
          small,
          Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: 1200,
            frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: child,
            ),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Переход «размыть и проявить»: старый экран остаётся под новым и
/// размывается, поверх проявляется фон приложения, потом сам экран.
/// Когда переход закончен, размытия больше нет (оно дорогое при прокрутке).
class BlurPageRoute<T> extends PageRouteBuilder<T> {
  BlurPageRoute({
    required WidgetBuilder builder,
    Duration duration = const Duration(milliseconds: 520),
    this.pageFrom = .5,
  }) : super(
         // Во время перехода старый экран всё равно виден (так устроены переходы
         // Flutter), а после — уходит со сцены: не рисуется и не ловит нажатия.
         opaque: true,
         transitionDuration: duration,
         reverseTransitionDuration: duration * .8,
         pageBuilder: (context, _, _) => builder(context),
       );

  /// С какой доли перехода проявляется сам экран (до неё — только размытие).
  final double pageFrom;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final blur = CurvedAnimation(parent: animation, curve: const Interval(0, .55));
    final background = CurvedAnimation(
      parent: animation,
      curve: Interval(pageFrom * .6, pageFrom + (1 - pageFrom) * .5, curve: Curves.easeOut),
    );
    final page = CurvedAnimation(
      parent: animation,
      curve: Interval(pageFrom, 1, curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final settled = animation.status == AnimationStatus.completed;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (!settled && blur.value > 0)
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18 * blur.value, sigmaY: 18 * blur.value),
                child: const SizedBox.expand(),
              ),
            Opacity(
              opacity: settled ? 1 : background.value,
              child: const GlowBackground(child: SizedBox.expand()),
            ),
            // Экран строится и раскладывается сразу, пока не виден.
            Opacity(opacity: settled ? 1 : page.value, child: child),
          ],
        );
      },
    );
  }
}
