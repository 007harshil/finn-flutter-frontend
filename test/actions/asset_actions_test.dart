import 'package:finn/actions/dispatcher.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/features/net_worth/application/asset_actions.dart';
import 'package:finn/features/net_worth/domain/asset.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

AssetInput gold(int rupees, {String name = 'Gold coins', DateTime? valuedOn, String? note}) => AssetInput(
      name: name,
      type: AssetType.gold,
      value: Money.rupees(rupees),
      valuedOn: valuedOn ?? DateTime(2026, 10, 1),
      note: note,
    );

void main() {
  late ActionHarness h;
  setUp(() async => h = await ActionHarness.create());

  group('assets.create', () {
    test('adds to net worth without touching cash (low risk)', () async {
      final out = await h.dispatcher.dispatch(const CreateAssetAction(), gold(80000, note: '  '), idempotencyKey: 'k');
      final a = (out as ActionCompleted<Asset>).value;
      expect(a.note, isNull, reason: 'blank notes are dropped');
      expect(a.valuedOn, DateTime(2026, 10, 1));
      final s = await h.snapshot();
      expect(s.balance.cash, harnessOpening);
      expect(s.netWorth.assets, const Money.rupees(80000));
      expect(s.netWorth.netWorth, harnessOpening + const Money.rupees(80000));
    });

    test('zero is a valid value; a duplicate name only warns', () async {
      await h.run(const CreateAssetAction(), gold(0));
      final dup = await h.dispatcher.preview(const CreateAssetAction(), gold(1000, name: 'gold COINS'));
      expect(dup.valueOrNull!.warnings, ['You already have an asset called "gold COINS".']);
    });

    test('validation', () async {
      Future<Iterable<String>> fields(AssetInput i) async => (await h.reject(const CreateAssetAction(), i)).fieldErrors.keys;
      expect(await fields(gold(1, name: 'G')), ['name']);
      expect(await fields(gold(1, name: 'x' * 41)), ['name']);
      expect(await fields(gold(-1)), ['value']);
      expect(await fields(gold(10000000001)), ['value']);
      expect(await fields(gold(1, valuedOn: DateTime(2026, 10, 11))), ['valuedOn']);
      expect(await fields(gold(1, note: 'n' * 501)), ['note']);
    });
  });

  group('assets.update and assets.delete', () {
    late Asset a;
    setUp(() async => a = await h.run(const CreateAssetAction(), gold(80000)));

    test('revaluation shows the net-worth effect and bumps the version', () async {
      final preview = (await h.dispatcher.preview(
              const UpdateAssetAction(), UpdateAssetInput(id: a.id, expectedVersion: 1, data: gold(95000))))
          .valueOrNull!;
      expect(preview.lines.last.label, 'Net worth effect');
      expect(preview.lines.last.value, '+₹15,000');
      final u = await h.run(const UpdateAssetAction(), UpdateAssetInput(id: a.id, expectedVersion: 1, data: gold(95000)));
      expect(u.version, 2);
      expect((await h.snapshot()).netWorth.assets, const Money.rupees(95000));
      expect((await h.reject(const UpdateAssetAction(), UpdateAssetInput(id: a.id, expectedVersion: 1, data: gold(1)))).code,
          FailureCode.staleData);
      expect((await h.reject(const UpdateAssetAction(), UpdateAssetInput(id: 'nope', expectedVersion: 1, data: gold(1)))).code,
          FailureCode.notFound);
    });

    test('delete is reviewed and lowers net worth only', () async {
      final asked = await h.dispatcher.dispatch(const DeleteAssetAction(), DeleteAssetInput(id: a.id), idempotencyKey: 'd');
      expect(asked, isA<ActionNeedsConfirmation<Asset>>());
      await h.run(const DeleteAssetAction(), DeleteAssetInput(id: a.id));
      final s = await h.snapshot();
      expect(s.assets, isEmpty);
      expect(s.netWorth.netWorth, harnessOpening);
    });
  });
}
