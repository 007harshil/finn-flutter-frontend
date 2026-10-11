import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Calendar helpers. All financial dates in FiNN are *calendar dates*:
/// `DateTime` values normalised to local midnight via [DateOnlyX.dateOnly].
/// Day differences are computed in UTC to stay correct across DST changes.
extension DateOnlyX on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);

  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  bool isSameMonth(DateTime other) =>
      year == other.year && month == other.month;

  DateTime get startOfMonth => DateTime(year, month);

  DateTime get endOfMonth => DateTime(year, month + 1, 0);

  int get daysInMonth => DateTime(year, month + 1, 0).day;

  MonthKey get monthKey => MonthKey(year, month);

  bool isOnOrBefore(DateTime other) => !dateOnly.isAfter(other.dateOnly);
  bool isOnOrAfter(DateTime other) => !dateOnly.isBefore(other.dateOnly);
}

/// Whole calendar days from [from] to [to] (negative when [to] is earlier).
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Adds [months] to [date], clamping the day to the target month's length.
///
/// `addMonthsClamped(Jan 31, 1)` → Feb 28 (or 29 in a leap year).
/// When [anchorDay] is provided it is used instead of `date.day`, so a
/// schedule anchored on the 31st returns to the 31st after a short month.
DateTime addMonthsClamped(DateTime date, int months, {int? anchorDay}) {
  final totalMonths = date.year * 12 + (date.month - 1) + months;
  final year = totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = (anchorDay ?? date.day).clamp(1, lastDay);
  return DateTime(year, month, day);
}

bool isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// A calendar month, e.g. October 2026.
@immutable
class MonthKey implements Comparable<MonthKey> {
  const MonthKey(this.year, this.month)
      : assert(month >= 1 && month <= 12, 'month out of range');

  factory MonthKey.fromDate(DateTime d) => MonthKey(d.year, d.month);

  /// Parses `yyyy-MM`.
  static MonthKey? tryParse(String? value) {
    if (value == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(value);
    if (m == null) return null;
    final month = int.parse(m.group(2)!);
    if (month < 1 || month > 12) return null;
    return MonthKey(int.parse(m.group(1)!), month);
  }

  final int year;
  final int month;

  DateTime get start => DateTime(year, month);
  DateTime get end => DateTime(year, month + 1, 0);
  DateRange get range => DateRange(start, end);
  int get dayCount => end.day;

  MonthKey get next => MonthKey.fromDate(DateTime(year, month + 1));
  MonthKey get previous => MonthKey.fromDate(DateTime(year, month - 1));
  MonthKey shift(int months) => MonthKey.fromDate(DateTime(year, month + months));

  bool contains(DateTime d) => d.year == year && d.month == month;

  /// `2026-10`
  String get id => '$year-${month.toString().padLeft(2, '0')}';

  @override
  int compareTo(MonthKey other) =>
      (year * 12 + month).compareTo(other.year * 12 + other.month);

  bool operator <(MonthKey o) => compareTo(o) < 0;
  bool operator >(MonthKey o) => compareTo(o) > 0;
  bool operator <=(MonthKey o) => compareTo(o) <= 0;
  bool operator >=(MonthKey o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) =>
      other is MonthKey && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => id;
}

/// Inclusive range of calendar dates.
@immutable
class DateRange {
  DateRange(DateTime start, DateTime end)
      : start = start.dateOnly,
        end = end.dateOnly,
        assert(!end.dateOnly.isBefore(start.dateOnly), 'end before start');

  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) {
    final d = date.dateOnly;
    return !d.isBefore(start) && !d.isAfter(end);
  }

  int get dayCount => daysBetween(start, end) + 1;

  /// The range of equal length immediately before this one.
  DateRange get previous {
    final len = dayCount;
    final prevEnd = start.subtract(const Duration(days: 1)).dateOnly;
    final prevStart = DateTime(prevEnd.year, prevEnd.month, prevEnd.day - len + 1);
    return DateRange(prevStart, prevEnd);
  }

  bool overlaps(DateRange other) =>
      !other.end.isBefore(start) && !other.start.isAfter(end);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start → $end)';
}

/// Cached `intl` formatters. Creating `DateFormat` instances is relatively
/// expensive, so list rows must use these shared instances.
class DateFormats {
  DateFormats._();

  // English month/day names are identical for en_IN and the built-in
  // default locale, which needs no async initialisation.

  static final DateFormat dayMonth = DateFormat('d MMM');
  static final DateFormat dayMonthYear = DateFormat('d MMM yyyy');
  static final DateFormat weekdayDayMonth = DateFormat('EEEE, d MMM');
  static final DateFormat shortWeekdayDayMonth = DateFormat('EEE, d MMM');
  static final DateFormat monthYear = DateFormat('MMMM yyyy');
  static final DateFormat shortMonthYear = DateFormat('MMM yy');
  static final DateFormat shortMonth = DateFormat('MMM');
  static final DateFormat iso = DateFormat('yyyy-MM-dd');
  static final DateFormat timestamp = DateFormat('d MMM yyyy, h:mm a');

  /// "Today", "Yesterday", "Tomorrow", or `d MMM yyyy`.
  static String relativeDay(DateTime date, DateTime today) {
    final diff = daysBetween(today, date);
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    return date.year == today.year ? dayMonth.format(date) : dayMonthYear.format(date);
  }

  /// "in 3 days", "today", "2 days ago", "overdue by 5 days" style phrase.
  static String dueIn(DateTime due, DateTime today) {
    final diff = daysBetween(today, due);
    if (diff == 0) return 'due today';
    if (diff == 1) return 'due tomorrow';
    if (diff > 1) return 'due in $diff days';
    if (diff == -1) return 'overdue by 1 day';
    return 'overdue by ${-diff} days';
  }
}
