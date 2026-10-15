import 'package:finn/core/money/money.dart';
import 'package:finn/core/time/dates.dart';
import 'package:finn/features/transactions/application/transaction_filter.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx(
  String id,
  int rupees,
  DateTime date, {
  TransactionType type = TransactionType.expense,
  String category = 'food',
  String accountId = 'acc_cash',
  String? channel,
  TransactionOrigin origin = TransactionOrigin.manual,
}) =>
    Transaction(
      id: id,
      type: type,
      amount: Money.rupees(rupees),
      categoryId: category,
      date: date,
      createdAt: date,
      updatedAt: date,
      accountId: accountId,
      channel: channel,
      origin: origin,
    );

void main() {
  final today = DateTime(2026, 10, 11);
  final txs = [
    _tx('salary', 100000, DateTime(2026, 10, 10), type: TransactionType.income, category: 'salary'),
    _tx('rent', 30000, DateTime(2026, 10, 5), category: 'rent', accountId: 'acc_axis'),
    _tx('netflix', 649, DateTime(2026, 10, 3), category: 'subs', origin: TransactionOrigin.subscription),
    _tx('lunch', 450, DateTime(2026, 10, 2), accountId: 'acc_sbi'),
    _tx('dinner', 1800, DateTime(2026, 10, 1), accountId: 'acc_hdfc'),
    // September: inside the comparison window (1–11 Sep) and after it.
    _tx('sep-early', 5000, DateTime(2026, 9, 8), accountId: 'acc_sbi'),
    _tx('sep-late', 9000, DateTime(2026, 9, 25), accountId: 'acc_sbi'),
  ];
  final october = TransactionFilter(month: today.monthKey);
  TransactionFeed feed(TransactionFilter f) => TransactionQuery.build(txs, f, const {}, today: today);
  List<String> ids(TransactionFilter f) => feed(f).transactions.map((t) => t.id).toList();

  test('amount range keeps inclusive bounds and open ends', () {
    expect(ids(october.copyWith(amount: () => const AmountRange(minPaise: 45000, maxPaise: 180000))),
        ['netflix', 'lunch', 'dinner']);
    expect(ids(october.copyWith(amount: () => const AmountRange(maxPaise: 50000))), ['lunch']);
    expect(ids(october.copyWith(amount: () => const AmountRange(minPaise: 3000000))), ['salary', 'rent']);
  });

  test('account filter keeps transactions on the chosen accounts', () {
    expect(ids(october.copyWith(accountIds: {'acc_sbi', 'acc_hdfc'})), ['lunch', 'dinner']);
    expect(ids(october.copyWith(accountIds: {'acc_cash'})), ['salary', 'netflix']);
  });

  test('channel filter matches case-insensitively', () {
    final withChannels = [
      _tx('a', 100, DateTime(2026, 10, 2), channel: 'UPI'),
      _tx('b', 200, DateTime(2026, 10, 3), channel: 'ATM'),
      _tx('c', 300, DateTime(2026, 10, 4)),
    ];
    final f = october.copyWith(channels: {'upi'});
    expect(TransactionQuery.build(withChannels, f, const {}, today: today).transactions.map((t) => t.id), ['a']);
  });

  test('source filter matches the transaction origin', () {
    expect(ids(october.copyWith(origins: {TransactionOrigin.subscription})), ['netflix']);
  });

  test('advanced count and refinements include the new filters', () {
    final f = october.copyWith(
      amount: () => const AmountRange(maxPaise: 100),
      accountIds: {'acc_cash'},
      origins: {TransactionOrigin.manual},
      categoryIds: {'food'},
    );
    expect(f.advancedCount, 4);
    expect(f.hasRefinements, isTrue);
    expect(october.advancedCount, 0);
    expect(october.hasRefinements, isFalse);
  });

  test('compares the current month with the same days of last month', () {
    final f = feed(october);
    expect(f.expense, const Money.rupees(30000 + 649 + 450 + 1800));
    expect(f.previousExpense, const Money.rupees(5000));
    // Filters apply to the comparison too.
    expect(feed(october.copyWith(accountIds: {'acc_hdfc'})).previousExpense, Money.zero);
    // A past month compares with the whole month before it.
    expect(TransactionQuery.previousPeriod(TransactionFilter(month: const MonthKey(2026, 9)), today),
        DateRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31)));
  });

  test('daily spend, category shares and largest expense', () {
    final f = feed(october);
    expect(f.dailyExpense.length, 31);
    expect(f.dailyExpense[0], 180000);
    expect(f.dailyExpense[4], 3000000);
    expect(f.expenseByCategory.first.categoryId, 'rent');
    expect(f.expenseByCategory.map((s) => s.categoryId), ['rent', 'food', 'subs']);
    expect(f.expenseByCategory[1].count, 2);
    expect(f.incomeByCategory.single.categoryId, 'salary');
    expect(f.largestExpense?.id, 'rent');
  });

  test('live count matches the built feed', () {
    final f = october.copyWith(accountIds: {'acc_sbi'});
    expect(TransactionQuery.count(txs, f, const {}), feed(f).count);
  });
}
