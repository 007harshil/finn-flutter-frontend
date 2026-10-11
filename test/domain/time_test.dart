import 'package:finn/core/money/money.dart';
import 'package:finn/core/time/clock.dart';
import 'package:finn/core/time/dates.dart';
import 'package:finn/core/time/frequency.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  group('addMonthsClamped', () {
    test('clamps to the end of shorter months', () {
      expect(addMonthsClamped(d(2026, 1, 31), 1), d(2026, 2, 28));
      expect(addMonthsClamped(d(2028, 1, 31), 1), d(2028, 2, 29)); // leap year
      expect(addMonthsClamped(d(2026, 3, 31), 1), d(2026, 4, 30));
      expect(addMonthsClamped(d(2026, 8, 31), 1), d(2026, 9, 30));
      expect(addMonthsClamped(d(2028, 2, 29), 12), d(2029, 2, 28));
      expect(addMonthsClamped(d(2028, 2, 29), 48), d(2032, 2, 29));
    });

    test('crosses year boundaries in both directions', () {
      expect(addMonthsClamped(d(2026, 12, 15), 1), d(2027, 1, 15));
      expect(addMonthsClamped(d(2026, 1, 15), -1), d(2025, 12, 15));
      expect(addMonthsClamped(d(2026, 3, 31), -1), d(2026, 2, 28));
      expect(addMonthsClamped(d(2026, 10, 10), -22), d(2024, 12, 10));
      expect(addMonthsClamped(d(2026, 10, 10), 0), d(2026, 10, 10));
    });

    test('anchorDay restores the original day after a short month', () {
      final feb = addMonthsClamped(d(2026, 1, 31), 1);
      expect(feb, d(2026, 2, 28));
      expect(addMonthsClamped(feb, 1), d(2026, 3, 28)); // without anchor: drifts
      expect(addMonthsClamped(feb, 1, anchorDay: 31), d(2026, 3, 31));
      expect(addMonthsClamped(d(2026, 3, 31), 1, anchorDay: 31), d(2026, 4, 30));
      expect(addMonthsClamped(d(2028, 1, 30), 1, anchorDay: 30), d(2028, 2, 29));
    });

    test('drops the time of day', () {
      expect(addMonthsClamped(DateTime(2026, 1, 31, 18, 30), 1), d(2026, 2, 28));
    });
  });

  test('isLeapYear', () {
    expect(isLeapYear(2024), isTrue);
    expect(isLeapYear(2026), isFalse);
    expect(isLeapYear(2000), isTrue);
    expect(isLeapYear(1900), isFalse);
    expect(isLeapYear(2100), isFalse);
  });

  group('daysBetween', () {
    test('counts calendar days, ignoring time of day', () {
      expect(daysBetween(d(2026, 3, 1), d(2026, 4, 1)), 31);
      expect(daysBetween(d(2026, 4, 1), d(2026, 3, 1)), -31);
      expect(daysBetween(d(2026, 10, 10), d(2026, 10, 10)), 0);
      expect(daysBetween(DateTime(2026, 10, 10, 23, 59), DateTime(2026, 10, 11, 0, 1)), 1);
      expect(daysBetween(DateTime(2026, 10, 11, 0, 1), DateTime(2026, 10, 10, 23, 59)), -1);
      expect(daysBetween(d(2028, 2, 28), d(2028, 3, 1)), 2);
      expect(daysBetween(d(2026, 2, 28), d(2026, 3, 1)), 1);
      expect(daysBetween(d(2026, 1, 1), d(2027, 1, 1)), 365);
      expect(daysBetween(d(2028, 1, 1), d(2029, 1, 1)), 366);
    });

    test('is unaffected by DST transitions in any locale', () {
      // US (8 Mar / 1 Nov 2026) and EU (29 Mar / 25 Oct 2026) switch dates.
      expect(daysBetween(d(2026, 3, 7), d(2026, 3, 9)), 2);
      expect(daysBetween(d(2026, 3, 28), d(2026, 3, 30)), 2);
      expect(daysBetween(d(2026, 10, 24), d(2026, 10, 26)), 2);
      expect(daysBetween(d(2026, 10, 31), d(2026, 11, 2)), 2);
      expect(daysBetween(d(2026, 1, 1), d(2026, 12, 31)), 364);
    });
  });

  group('DateOnlyX', () {
    test('calendar helpers', () {
      final t = DateTime(2028, 2, 14, 17, 45);
      expect(t.dateOnly, d(2028, 2, 14));
      expect(t.startOfMonth, d(2028, 2, 1));
      expect(t.endOfMonth, d(2028, 2, 29));
      expect(t.daysInMonth, 29);
      expect(t.monthKey, const MonthKey(2028, 2));
      expect(t.isSameDay(d(2028, 2, 14)), isTrue);
      expect(t.isOnOrBefore(d(2028, 2, 14)) && t.isOnOrAfter(d(2028, 2, 14)), isTrue);
      expect(t.isOnOrAfter(d(2028, 2, 15)), isFalse);
    });

    test('FixedClock.today is local midnight', () {
      final c = FixedClock(DateTime(2026, 10, 10, 9, 30));
      expect(c.today(), d(2026, 10, 10));
      c.advance(const Duration(hours: 15));
      expect(c.today(), d(2026, 10, 11));
    });
  });

  group('MonthKey', () {
    test('shift, next and previous wrap years', () {
      const oct = MonthKey(2026, 10);
      expect(oct.next, const MonthKey(2026, 11));
      expect(const MonthKey(2026, 12).next, const MonthKey(2027, 1));
      expect(const MonthKey(2026, 1).previous, const MonthKey(2025, 12));
      expect(oct.shift(-10), const MonthKey(2025, 12));
      expect(oct.shift(15), const MonthKey(2028, 1));
      expect(oct.shift(-22), const MonthKey(2024, 12));
      expect(oct.shift(0), oct);
    });

    test('compare and order', () {
      const a = MonthKey(2025, 12);
      const b = MonthKey(2026, 1);
      expect(a < b && b > a && a <= a && b >= b, isTrue);
      expect(a.compareTo(b), lessThan(0));
      expect(([b, a, const MonthKey(2024, 6)]..sort()).map((m) => m.id), ['2024-06', '2025-12', '2026-01']);
      expect(a == const MonthKey(2025, 12), isTrue);
      expect({a, MonthKey.fromDate(d(2025, 12, 5))}.length, 1);
    });

    test('parse and id', () {
      expect(MonthKey.tryParse('2026-10'), const MonthKey(2026, 10));
      expect(MonthKey.tryParse('2026-01')!.id, '2026-01');
      expect(MonthKey.tryParse('2026-13'), isNull);
      expect(MonthKey.tryParse('2026-00'), isNull);
      expect(MonthKey.tryParse('2026-1'), isNull);
      expect(MonthKey.tryParse('26-10'), isNull);
      expect(MonthKey.tryParse(null), isNull);
      expect(const MonthKey(2026, 3).toString(), '2026-03');
    });

    test('range, day count, contains', () {
      const feb = MonthKey(2028, 2);
      expect(feb.start, d(2028, 2, 1));
      expect(feb.end, d(2028, 2, 29));
      expect(feb.dayCount, 29);
      expect(const MonthKey(2026, 2).dayCount, 28);
      expect(feb.range, DateRange(d(2028, 2, 1), d(2028, 2, 29)));
      expect(feb.contains(DateTime(2028, 2, 29, 23)), isTrue);
      expect(feb.contains(d(2028, 3, 1)), isFalse);
      expect(MonthKey.fromDate(d(2026, 10, 10)), const MonthKey(2026, 10));
    });
  });

  group('DateRange', () {
    test('normalises to dates and is inclusive', () {
      final r = DateRange(DateTime(2026, 10, 1, 13), DateTime(2026, 10, 31, 8));
      expect(r.start, d(2026, 10, 1));
      expect(r.end, d(2026, 10, 31));
      expect(r.dayCount, 31);
      expect(r.contains(DateTime(2026, 10, 31, 23, 59)), isTrue);
      expect(r.contains(d(2026, 10, 1)), isTrue);
      expect(r.contains(d(2026, 9, 30)), isFalse);
      expect(r.contains(d(2026, 11, 1)), isFalse);
    });

    test('previous is the adjacent range of equal length', () {
      final oct = DateRange(d(2026, 10, 1), d(2026, 10, 31));
      expect(oct.previous, DateRange(d(2026, 8, 31), d(2026, 9, 30)));
      final mar = DateRange(d(2026, 3, 1), d(2026, 3, 31));
      expect(mar.previous, DateRange(d(2026, 1, 29), d(2026, 2, 28)));
      final week = DateRange(d(2027, 1, 3), d(2027, 1, 9));
      expect(week.previous, DateRange(d(2026, 12, 27), d(2027, 1, 2)));
      final day = DateRange(d(2026, 1, 1), d(2026, 1, 1));
      expect(day.previous, DateRange(d(2025, 12, 31), d(2025, 12, 31)));
      for (final r in [oct, mar, week, day]) {
        expect(r.previous.dayCount, r.dayCount);
        expect(daysBetween(r.previous.end, r.start), 1);
      }
    });

    test('overlaps', () {
      final a = DateRange(d(2026, 1, 1), d(2026, 1, 10));
      expect(a.overlaps(DateRange(d(2026, 1, 10), d(2026, 1, 20))), isTrue);
      expect(a.overlaps(DateRange(d(2026, 1, 11), d(2026, 1, 20))), isFalse);
      expect(a.overlaps(DateRange(d(2025, 12, 1), d(2026, 1, 1))), isTrue);
    });
  });

  group('Frequency', () {
    test('nth keeps the anchor day of the start date', () {
      final start = d(2026, 1, 31);
      expect(Frequency.monthly.nth(start, 0), start);
      expect(Frequency.monthly.nth(start, 1), d(2026, 2, 28));
      expect(Frequency.monthly.nth(start, 2), d(2026, 3, 31));
      expect(Frequency.monthly.nth(start, 3), d(2026, 4, 30));
      expect(Frequency.monthly.nth(start, 12), d(2027, 1, 31));
      expect(Frequency.monthly.nth(d(2027, 12, 31), 2), d(2028, 2, 29));
      expect(Frequency.quarterly.nth(d(2026, 11, 30), 1), d(2027, 2, 28));
      expect(Frequency.quarterly.nth(d(2026, 11, 30), 2), d(2027, 5, 30));
      expect(Frequency.halfYearly.nth(d(2026, 8, 31), 1), d(2027, 2, 28));
      expect(Frequency.yearly.nth(d(2028, 2, 29), 1), d(2029, 2, 28));
      expect(Frequency.yearly.nth(d(2028, 2, 29), 4), d(2032, 2, 29));
      expect(Frequency.weekly.nth(d(2026, 12, 25), 3), d(2027, 1, 15));
    });

    test('next steps one period, honouring anchorDay', () {
      expect(Frequency.monthly.next(d(2026, 1, 31)), d(2026, 2, 28));
      expect(Frequency.monthly.next(d(2026, 2, 28)), d(2026, 3, 28));
      expect(Frequency.monthly.next(d(2026, 2, 28), anchorDay: 31), d(2026, 3, 31));
      expect(Frequency.weekly.next(d(2026, 10, 29)), d(2026, 11, 5));
      expect(Frequency.yearly.next(d(2026, 10, 10)), d(2027, 10, 10));
    });

    test('monthlyEquivalent: weekly is x52/12, others divide by months (half-up)', () {
      Money r(int v) => Money.rupees(v);
      expect(Frequency.weekly.monthlyEquivalent(r(100)), Money.fromPaise(43333)); // 433.333…
      expect(Frequency.weekly.monthlyEquivalent(r(3)), Money.fromPaise(1300)); // exactly 13
      expect(Frequency.weekly.monthlyEquivalent(Money.fromPaise(1)), Money.fromPaise(4)); // 4.33 → 4
      expect(Frequency.monthly.monthlyEquivalent(r(499)), r(499));
      expect(Frequency.quarterly.monthlyEquivalent(r(999)), r(333));
      expect(Frequency.halfYearly.monthlyEquivalent(r(100)), Money.fromPaise(1667)); // 16.666…
      expect(Frequency.yearly.monthlyEquivalent(r(1000)), Money.fromPaise(8333)); // 83.333…
      expect(Frequency.yearly.monthlyEquivalent(r(1499)), Money.fromPaise(12492)); // 124.9166…
    });

    test('annualized and periods per year', () {
      expect(Frequency.weekly.annualized(const Money.rupees(100)), const Money.rupees(5200));
      expect(Frequency.quarterly.annualized(const Money.rupees(999)), const Money.rupees(3996));
      expect(Frequency.values.map((f) => f.periodsPerYear), [52, 12, 4, 2, 1]);
    });
  });
}
