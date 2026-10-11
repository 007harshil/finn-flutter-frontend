import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../domain/asset.dart';
import '../domain/net_worth.dart';

/// Valuations older than this are flagged so the user can refresh them.
const int assetStaleAfterDays = 180;

/// One asset with presentation-ready facts.
@immutable
class AssetRow {
  const AssetRow({required this.asset, required this.stale, required this.shareBps});

  final Asset asset;

  /// The valuation is older than [assetStaleAfterDays].
  final bool stale;

  /// Share of all asset entries' value, in basis points.
  final int shareBps;
}

/// A slice of what the user owns (for the composition bar).
@immutable
class OwnSlice {
  const OwnSlice({required this.group, required this.label, required this.amount, required this.fraction});

  final NetWorthGroup group;
  final String label;
  final Money amount;

  /// 0–1 share of total assets.
  final double fraction;
}

/// Everything the net worth screen shows, precomputed.
@immutable
class NetWorthView {
  const NetWorthView({
    required this.snapshot,
    required this.assets,
    required this.receivables,
    required this.liabilities,
    required this.slices,
  });

  final NetWorthSnapshot snapshot;

  /// Asset entries, highest value first.
  final List<AssetRow> assets;
  final List<NetWorthLine> receivables;
  final List<NetWorthLine> liabilities;

  /// Non-empty parts of what the user owns, largest first.
  final List<OwnSlice> slices;

  /// Liabilities as a share of total assets (basis points); null when the
  /// user owns nothing.
  int? get debtRatioBps {
    final total = snapshot.totalAssets;
    if (!total.isPositive) return null;
    return (snapshot.liabilities.paise * 10000 / total.paise).round();
  }

  int get staleCount => assets.where((a) => a.stale).length;
}

NetWorthView buildNetWorthView(NetWorthSnapshot s, List<Asset> assets, DateTime today) {
  final total = Money.sum(assets.map((a) => a.value));
  final rows = [
    for (final a in assets)
      AssetRow(
        asset: a,
        stale: today.difference(a.valuedOn).inDays > assetStaleAfterDays,
        shareBps: total.isPositive ? (a.value.paise * 10000 / total.paise).round() : 0,
      ),
  ]..sort((a, b) {
      final c = b.asset.value.compareTo(a.asset.value);
      return c != 0 ? c : a.asset.name.toLowerCase().compareTo(b.asset.name.toLowerCase());
    });
  final own = s.totalAssets;
  OwnSlice slice(NetWorthGroup g, String label, Money m) =>
      OwnSlice(group: g, label: label, amount: m, fraction: own.isPositive ? m.paise / own.paise : 0);
  final slices = [
    slice(NetWorthGroup.cash, 'Cash & bank', s.cash),
    slice(NetWorthGroup.assets, 'Assets', s.assets),
    slice(NetWorthGroup.receivables, 'Owed to you', s.receivables),
  ].where((x) => x.amount.isPositive).toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
  return NetWorthView(
    snapshot: s,
    assets: rows,
    receivables: s.lines.where((l) => l.group == NetWorthGroup.receivables).toList(),
    liabilities: s.lines.where((l) => l.group == NetWorthGroup.liabilities).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount)),
    slices: slices,
  );
}

final netWorthViewProvider = Provider<AsyncValue<NetWorthView>>((ref) {
  final today = ref.watch(todayProvider);
  final assets = ref.watch(assetsProvider);
  return ref.watch(netWorthProvider).whenData((s) => buildNetWorthView(s, assets.value ?? const [], today));
});

/// Single asset lookup for the edit sheet.
final assetByIdProvider = Provider.family<AsyncValue<Asset?>, String>(
    (ref, id) => ref.watch(assetsProvider).whenData((list) => list.where((a) => a.id == id).firstOrNull));
