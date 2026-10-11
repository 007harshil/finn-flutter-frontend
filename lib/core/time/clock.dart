import 'dates.dart';

/// Source of the current time. Inject a [FixedClock] in tests and mock
/// scenarios so due-date calculations are deterministic.
abstract interface class Clock {
  DateTime now();
}

extension ClockX on Clock {
  /// Today's calendar date (local midnight).
  DateTime today() => now().dateOnly;
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

class FixedClock implements Clock {
  FixedClock(this._now);

  DateTime _now;

  void advance(Duration by) => _now = _now.add(by);
  void set(DateTime value) => _now = value;

  @override
  DateTime now() => _now;
}
