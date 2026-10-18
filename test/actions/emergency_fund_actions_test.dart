import 'package:finn/actions/dispatcher.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/emergency_fund/application/emergency_actions.dart';
import 'package:finn/features/emergency_fund/domain/emergency_fund.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

ConfigureEmergencyFundInput plan(int essentials, int months, {int? override}) => ConfigureEmergencyFundInput(
      essentialMonthlyExpenses: Money.rupees(essentials),
      targetMonths: months,
      targetOverride: override == null ? null : Money.rupees(override),
    );

EmergencyFundMovementInput move(int rupees, {DateTime? date}) =>
    EmergencyFundMovementInput(amount: Money.rupees(rupees), date: date ?? DateTime(2026, 10, 10));

void main() {
  late ActionHarness h;
  setUp(() async => h = await ActionHarness.create());

  group('emergencyFund.configure', () {
    test('sets the plan without moving money (low risk)', () async {
      final out = await h.dispatcher.dispatch(const ConfigureEmergencyFundAction(), plan(40000, 6), idempotencyKey: 'k');
      final p = (out as ActionCompleted<EmergencyFundPlan>).value;
      expect(p.target, const Money.rupees(240000));
      expect(p.updatedAt, harnessNow);
      expect(out.preview.summary, 'Emergency fund target ₹2,40,000');
      final s = await h.snapshot();
      expect(s.emergencyPlan, isNotNull);
      expect(s.emergency.level, EmergencyFundLevel.critical);
      expect(s.balance.available, harnessOpening);
    });

    test('an explicit target replaces essentials × months', () async {
      final p = await h.run(const ConfigureEmergencyFundAction(), plan(40000, 6, override: 100000));
      expect(p.target, const Money.rupees(100000));
    });

    test('validation', () async {
      Future<Iterable<String>> fields(ConfigureEmergencyFundInput i) async =>
          (await h.reject(const ConfigureEmergencyFundAction(), i)).fieldErrors.keys;
      expect(await fields(plan(0, 6)), ['essentialMonthlyExpenses']);
      expect(await fields(plan(1000000001, 6)), ['essentialMonthlyExpenses']);
      expect(await fields(plan(40000, 0)), ['targetMonths']);
      expect(await fields(plan(40000, 25)), ['targetMonths']);
      expect(await fields(plan(40000, 6, override: 0)), ['targetOverride']);
      await h.run(const ConfigureEmergencyFundAction(), plan(40000, 24));
      await h.run(const ConfigureEmergencyFundAction(), plan(40000, 1));
    });
  });

  group('contributions and withdrawals', () {
    setUp(() async => h.run(const ConfigureEmergencyFundAction(), plan(10000, 6)));

    test('contributions earmark available cash: not spending, net worth unchanged', () async {
      final asked = await h.dispatcher.dispatch(const EmergencyFundMovementAction.contribute(), move(30000), idempotencyKey: 'k');
      final lines = {for (final l in (asked as ActionNeedsConfirmation).preview.lines) l.label: l.value};
      expect(lines['Emergency fund'], '₹0 → ₹30,000');
      expect(lines['Net worth'], 'Unchanged');

      final m = await h.run(const EmergencyFundMovementAction.contribute(), move(30000));
      expect(m.bucketType, SavingsBucketType.emergencyFund);
      expect(m.bucketId, SavingsMovement.emergencyFundBucketId);
      final s = await h.snapshot();
      expect(s.emergency.saved, const Money.rupees(30000));
      expect(s.emergency.coverageTenths, 30);
      expect(s.balance.cash, harnessOpening);
      expect(s.balance.available, harnessOpening - const Money.rupees(30000));
      expect(s.netWorth.netWorth, harnessOpening);
      expect(s.transactions, isEmpty);
    });

    test('reaching the target is celebrated; withdrawals are reassured', () async {
      final full = await h.dispatcher.preview(const EmergencyFundMovementAction.contribute(), move(60000));
      expect(full.valueOrNull!.warnings, ['This fully funds your emergency target!']);
      await h.run(const EmergencyFundMovementAction.contribute(), move(60000));
      expect((await h.snapshot()).emergency.level, EmergencyFundLevel.funded);
      final out = await h.dispatcher.preview(const EmergencyFundMovementAction.withdraw(), move(1000));
      expect(out.valueOrNull!.warnings.single, startsWith('Using your safety net is okay'));
    });

    test('withdrawals release money back to available', () async {
      await h.run(const EmergencyFundMovementAction.contribute(), move(30000));
      await h.run(const EmergencyFundMovementAction.withdraw(), move(10000));
      final s = await h.snapshot();
      expect(s.emergency.saved, const Money.rupees(20000));
      expect(s.balance.available, harnessOpening - const Money.rupees(20000));
    });

    test('limits: available cash, saved amount, dates, note length', () async {
      final tooMuch = await h.reject(const EmergencyFundMovementAction.contribute(), move(100001));
      expect(tooMuch.fieldErrors['amount'], 'Only ₹1,00,000 in Cash is free to set aside.');
      final overdraw = await h.reject(const EmergencyFundMovementAction.withdraw(), move(1));
      expect(overdraw.fieldErrors['amount'], 'Only ₹0 is in your emergency fund.');
      expect((await h.reject(const EmergencyFundMovementAction.contribute(), move(1, date: DateTime(2026, 10, 11))))
          .fieldErrors
          .keys, ['date']);
      expect((await h.reject(const EmergencyFundMovementAction.contribute(), move(0))).fieldErrors.keys, ['amount']);
      final longNote = EmergencyFundMovementInput(amount: const Money.rupees(1), date: DateTime(2026, 10, 1), note: 'n' * 201);
      expect((await h.reject(const EmergencyFundMovementAction.contribute(), longNote)).fieldErrors.keys, ['note']);
    });

    test('nothing to set aside when available is not positive', () async {
      await h.run(
        const CreateTransactionAction(),
        TransactionInput(type: TransactionType.expense, amount: const Money.rupees(100000), categoryId: SeedCategoryIds.rent, date: DateTime(2026, 10, 1)),
      );
      final f = await h.reject(const EmergencyFundMovementAction.contribute(), move(1));
      expect(f.fieldErrors['amount'], 'There is no free money in Cash to set aside.');
    });
  });
}
