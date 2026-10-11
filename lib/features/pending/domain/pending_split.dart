import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import 'pending_payment.dart';

/// How a bill is divided between the people in a split.
enum SplitMethod {
  equally('Equally', 'Everyone pays the same.'),
  exact('Exact amounts', 'Enter what each person pays. It must add up to the total.'),
  percent('Percentages', 'Give each person a percentage. It must add up to 100%.'),
  shares('Shares', 'Split by parts, e.g. 2 : 1 : 1 when one person had double.'),
  adjustment('Adjust', 'Split equally, then add or take off an amount per person.');

  const SplitMethod(this.label, this.hint);
  final String label;
  final String hint;

  /// Whether each person enters a value (everything except [equally]).
  bool get takesValues => this != equally;
}

/// What a split item remembers about the bill it came from. A split is one
/// entry made with several people: each person gets their own pending item
/// (so each settles on their own), and all of them carry the same [id].
///
/// The bill total is never stored: it is [myShare] plus the items of the
/// split, so editing or deleting one item can never leave it out of step.
@immutable
class PendingSplit {
  const PendingSplit({
    required this.id,
    required this.method,
    required this.includesMe,
    this.myShare = Money.zero,
    this.part,
  });

  /// Same on every item of one split.
  final String id;
  final SplitMethod method;

  /// The user was part of the bill too. Their share is never owed.
  final bool includesMe;
  final Money myShare;

  /// This person's entered value, kept to show how their share was found:
  /// paise for [SplitMethod.exact] and [SplitMethod.adjustment] (may be
  /// negative), basis points for [SplitMethod.percent] (100% = 10000), a
  /// count for [SplitMethod.shares]. Null for [SplitMethod.equally].
  final int? part;

  /// "Equal share", "40%", "2 shares", "+₹100", "Exact amount".
  String get partLabel => switch (method) {
        SplitMethod.equally => 'Equal share',
        SplitMethod.exact => 'Exact amount',
        SplitMethod.percent => formatSplitPercent(part ?? 0),
        SplitMethod.shares => '${part ?? 0} ${part == 1 ? 'share' : 'shares'}',
        SplitMethod.adjustment => (part ?? 0) == 0
            ? 'Equal share'
            : '${part! > 0 ? '+' : '−'}${Money.fromPaise(part!.abs()).format()} adjusted',
      };

  PendingSplit withPart(int? value) =>
      PendingSplit(id: id, method: method, includesMe: includesMe, myShare: myShare, part: value);

  @override
  bool operator ==(Object other) =>
      other is PendingSplit &&
      other.id == id &&
      other.method == method &&
      other.includesMe == includesMe &&
      other.myShare == myShare &&
      other.part == part;

  @override
  int get hashCode => Object.hash(id, method, includesMe, myShare, part);
}

/// "40%", "33.33%".
String formatSplitPercent(int bps) {
  final whole = bps ~/ 100;
  final frac = bps.abs() % 100;
  if (frac == 0) return '$whole%';
  return '$whole.${frac.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}%';
}

/// Result of dividing a bill: one share per person (in the order given), or
/// the reason the values do not work.
@immutable
class SplitOutcome {
  const SplitOutcome(this.shares, {this.error});

  const SplitOutcome.invalid(String this.error) : shares = const [];

  final List<Money> shares;
  final String? error;

  bool get isValid => error == null;
}

/// Divides [total] between people with exact paise. Leftover paise from
/// rounding go to the earliest people first, so the user — always first
/// when they are part of the bill — absorbs them, never a friend.
abstract final class SplitCalculator {
  /// [values] has one entry per person; its meaning depends on [method]
  /// (see [PendingSplit.part]). Ignored for [SplitMethod.equally].
  static SplitOutcome compute(Money total, SplitMethod method, List<int> values) {
    final n = values.length;
    if (n == 0) return const SplitOutcome.invalid('Add the people to split with.');
    if (!total.isPositive) return const SplitOutcome.invalid('Enter the total amount first.');
    final t = total.paise;
    switch (method) {
      case SplitMethod.equally:
        return SplitOutcome(_apportion(t, List.filled(n, 1)));
      case SplitMethod.shares:
        if (values.any((v) => v < 0)) return const SplitOutcome.invalid('Shares cannot be negative.');
        if (values.every((v) => v == 0)) return const SplitOutcome.invalid('Give at least one person a share.');
        return SplitOutcome(_apportion(t, values));
      case SplitMethod.percent:
        if (values.any((v) => v < 0)) return const SplitOutcome.invalid('Percentages cannot be negative.');
        final sum = values.fold<int>(0, (a, b) => a + b);
        if (sum != 10000) {
          return SplitOutcome.invalid('Percentages add up to ${formatSplitPercent(sum)}, not 100%.');
        }
        return SplitOutcome(_apportion(t, values));
      case SplitMethod.exact:
        if (values.any((v) => v < 0)) return const SplitOutcome.invalid('Amounts cannot be negative.');
        final sum = values.fold<int>(0, (a, b) => a + b);
        if (sum < t) return SplitOutcome.invalid('${Money.fromPaise(t - sum).format()} of the total is not given to anyone yet.');
        if (sum > t) return SplitOutcome.invalid('The amounts are ${Money.fromPaise(sum - t).format()} more than the total.');
        return SplitOutcome([for (final v in values) Money.fromPaise(v)]);
      case SplitMethod.adjustment:
        final base = t - values.fold<int>(0, (a, b) => a + b);
        if (base < 0) return const SplitOutcome.invalid('The adjustments add up to more than the total.');
        final even = _apportion(base, List.filled(n, 1));
        final shares = [for (var i = 0; i < n; i++) even[i] + Money.fromPaise(values[i])];
        if (shares.any((s) => s.isNegative)) {
          return const SplitOutcome.invalid('A take-off is larger than that person’s equal share.');
        }
        return SplitOutcome(shares);
    }
  }

  /// Largest-remainder split of [paise] by [weights]: shares add up exactly.
  static List<Money> _apportion(int paise, List<int> weights) {
    final w = weights.fold<int>(0, (a, b) => a + b);
    final base = [for (final x in weights) paise * x ~/ w];
    var left = paise - base.fold<int>(0, (a, b) => a + b);
    final order = List.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final r = (paise * weights[b] % w).compareTo(paise * weights[a] % w);
        return r != 0 ? r : a.compareTo(b);
      });
    for (final i in order) {
      if (left == 0) break;
      if (weights[i] == 0) continue;
      base[i]++;
      left--;
    }
    return [for (final p in base) Money.fromPaise(p)];
  }
}

/// All items of one split, read together: the bill, the user's share, and
/// how far each person has settled.
@immutable
class PendingSplitView {
  const PendingSplitView({required this.split, required this.members});

  /// From the first member; every member carries the same split id, method
  /// and share of the user.
  final PendingSplit split;

  /// One per person, in the order they were added.
  final List<PendingView> members;

  PendingDirection get direction => members.first.payment.direction;
  String get purpose => members.first.payment.purpose;

  /// Everyone in the bill, the user included when they were part of it.
  int get people => members.length + (split.includesMe ? 1 : 0);

  Money get total => split.myShare + Money.sum(members.map((m) => m.payment.originalAmount));
  Money get outstanding => Money.sum(members.map((m) => m.outstanding));
  Money get settled => Money.sum(members.map((m) => m.settled));
  int get settledCount => members.where((m) => m.status == PendingStatus.settled).length;
  int get activeCount => members.where((m) => m.status.isActive).length;

  /// The split's method, or "Custom" once an edited amount left the rule.
  String get methodLabel {
    final methods = {for (final m in members) m.payment.split!.method};
    return methods.length == 1 ? methods.single.label : 'Custom';
  }

  /// Every split in [views], keyed by split id, members in creation order.
  static Map<String, PendingSplitView> collect(Iterable<PendingView> views) {
    final by = <String, List<PendingView>>{};
    for (final v in views) {
      final s = v.payment.split;
      if (s != null) by.putIfAbsent(s.id, () => []).add(v);
    }
    return {
      for (final e in by.entries)
        e.key: PendingSplitView(
          split: e.value.first.payment.split!,
          members: e.value..sort((a, b) {
            final r = a.payment.createdAt.compareTo(b.payment.createdAt);
            return r != 0 ? r : a.payment.id.compareTo(b.payment.id);
          }),
        ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is PendingSplitView && other.split == split && listEquals(other.members, members);

  @override
  int get hashCode => Object.hash(split, Object.hashAll(members));
}
