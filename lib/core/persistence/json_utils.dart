import '../money/money.dart';

/// Shared JSON conventions for DTOs: money as integer paise, calendar dates
/// as `yyyy-MM-dd`, instants as ISO-8601.
abstract final class J {
  static int money(Money m) => m.paise;
  static Money toMoney(Object? v) => Money.fromPaise((v as num).toInt());
  static Money? toMoneyOrNull(Object? v) => v == null ? null : toMoney(v);

  static String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime toDate(Object? v) {
    final s = v as String;
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2].substring(0, 2)));
  }

  static DateTime? toDateOrNull(Object? v) => v == null ? null : toDate(v);

  static String instant(DateTime d) => d.toIso8601String();
  static DateTime toInstant(Object? v) => DateTime.parse(v as String);

  static T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((e) => e.name == name, orElse: () => fallback);

  static T? enumOrNull<T extends Enum>(List<T> values, Object? name) =>
      name == null ? null : values.where((e) => e.name == name).firstOrNull;
}
