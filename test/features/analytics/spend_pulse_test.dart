import 'package:finn/core/money/money.dart';
import 'package:finn/core/time/dates.dart';
import 'package:finn/features/analytics/presentation/spend_pulse.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx(String id, TransactionType type, int rupees, DateTime date) => Transaction(
  id: id,
  type: type,
  amount: Money.rupees(rupees),
  categoryId: 'c',
  date: date,
  createdAt: date,
  updatedAt: date,
  accountId: 'a',
);

void main() {
  group('SpendPulse.build', () {
    final today = DateTime(2026, 10, 10);
    const month = MonthKey(2026, 10);
    final txs = [
      _tx('1', TransactionType.expense, 100, DateTime(2026, 10, 1)),
      _tx('2', TransactionType.expense, 50, DateTime(2026, 10, 3)),
      _tx('3', TransactionType.income, 9000, DateTime(2026, 10, 2)),
      _tx('4', TransactionType.expense, 70, DateTime(2026, 9, 2)),
      _tx('5', TransactionType.expense, 30, DateTime(2026, 9, 30)),
      _tx('6', TransactionType.expense, 999, DateTime(2026, 8, 1)),
    ];

    test('runs this month up to today and last month in full, expenses only', () {
      final p = SpendPulse.build(txs, month, today);
      expect(p.days, 31);
      expect(p.thisMonth.length, 10);
      expect(p.thisMonth.first, 10000);
      expect(p.thisMonth[2], 15000);
      expect(p.spent, 15000);
      expect(p.lastMonth.length, 30);
      expect(p.lastMonth.first, 0);
      expect(p.lastMonth.last, 10000);
    });

    test('compares the same day of last month, clamped to its length', () {
      final p = SpendPulse.build(txs, month, today);
      expect(p.lastBy(10), 7000);
      expect(p.lastBy(31), 10000);
    });

    test('a past month runs to its last day', () {
      final p = SpendPulse.build(txs, const MonthKey(2026, 9), today);
      expect(p.thisMonth.length, 30);
      expect(p.spent, 10000);
      expect(p.lastMonth.first, 99900);
    });
  });
}
