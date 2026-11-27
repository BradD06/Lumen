import 'dart:async';

/// Таймер сна: через сколько минут или в конце главы книга встаёт на паузу.
final class SleepTimer {
  SleepTimer({required this.onFire, this.onChange, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Варианты в окне таймера.
  static const choices = [
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  /// Пора на паузу.
  final void Function() onFire;

  /// Осталось меньше на минуту, таймер включили или выключили.
  final void Function()? onChange;
  final DateTime Function() _now;

  Timer? _timer;
  Timer? _minutes;
  DateTime? _end;
  var _endOfChapter = false;

  bool get isOn => _end != null || _endOfChapter;

  /// До конца главы.
  bool get endOfChapter => _endOfChapter;

  /// Сколько осталось; `null` — таймер по времени не включён.
  Duration? get remaining {
    final end = _end;
    if (end == null) return null;
    final left = end.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  void start(Duration after) {
    cancel(notify: false);
    _end = _now().add(after);
    _timer = Timer(after, _fire);
    _minutes = Timer.periodic(const Duration(seconds: 30), (_) => onChange?.call());
    onChange?.call();
  }

  void startEndOfChapter() {
    cancel(notify: false);
    _endOfChapter = true;
    onChange?.call();
  }

  /// Глава дочитана: если таймер ждал конца главы — пауза. `true` — сработал.
  bool chapterEnded() {
    if (!_endOfChapter) return false;
    _fire();
    return true;
  }

  void cancel({bool notify = true}) {
    _timer?.cancel();
    _minutes?.cancel();
    _timer = null;
    _minutes = null;
    _end = null;
    _endOfChapter = false;
    if (notify) onChange?.call();
  }

  void _fire() {
    cancel(notify: false);
    onFire();
    onChange?.call();
  }

  void dispose() => cancel(notify: false);
}
