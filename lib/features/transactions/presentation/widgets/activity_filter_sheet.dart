import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../kit/kit.dart';
import '../../../../shared/presentation/category_icons.dart';
import '../../../accounts/application/account_support.dart';
import '../../../accounts/domain/money_account.dart';
import '../../../accounts/domain/transfer.dart';
import '../../../categories/domain/category.dart';
import '../../application/transaction_filter.dart';
import '../../domain/transaction.dart';

/// Categories shown before "View all".
const int _visibleCategories = 6;

/// Quick amount bands offered as one-tap presets (rupees; null = open).
const List<(int?, int?)> _amountPresets = [
  (null, 500),
  (500, 2000),
  (2000, 10000),
  (10000, null),
];

/// Opens the Activity filter sheet; returns the chosen filter or null.
Future<TransactionFilter?> showActivityFilterSheet(
  BuildContext context,
  TransactionFilter current,
) => showFinnSheet<TransactionFilter>(
  context,
  builder: (_) => ActivityFilterSheet(initial: current),
);

/// Short label for an amount range ("₹500 – ₹2K", "Under ₹500", "Any amount").
String amountRangeLabel(AmountRange? r) {
  if (r == null || r.isOpen) return 'Any amount';
  String m(int paise) => MoneyFormatter.compact(Money.fromPaise(paise));
  if (r.minPaise == null) return 'Under ${m(r.maxPaise!)}';
  if (r.maxPaise == null) return 'Over ${m(r.minPaise!)}';
  return '${m(r.minPaise!)} – ${m(r.maxPaise!)}';
}

String originLabel(TransactionOrigin o) => switch (o) {
  TransactionOrigin.manual => 'Added by you',
  TransactionOrigin.subscription => 'Subscriptions',
  TransactionOrigin.loanRepayment => 'Loan EMIs',
  TransactionOrigin.loanDisbursement => 'Loan received',
  TransactionOrigin.pendingSettlement => 'Settlements',
};

IconData accountIcon(MoneyAccountKind k) => switch (k) {
  MoneyAccountKind.cash => LucideIcons.banknote,
  MoneyAccountKind.bank => LucideIcons.landmark,
  MoneyAccountKind.promoCard => LucideIcons.wallet,
  MoneyAccountKind.debitCard || MoneyAccountKind.creditCard || MoneyAccountKind.otherCard => LucideIcons.creditCard,
};

/// Type, amount, category, payment method and source in one sheet, with a
/// live count of matching transactions on the apply button.
class ActivityFilterSheet extends ConsumerStatefulWidget {
  const ActivityFilterSheet({super.key, required this.initial});

  final TransactionFilter initial;

  @override
  ConsumerState<ActivityFilterSheet> createState() =>
      _ActivityFilterSheetState();
}

class _ActivityFilterSheetState extends ConsumerState<ActivityFilterSheet> {
  late TransactionFilter _draft = widget.initial;
  bool _allCategories = false;

  void _set(TransactionFilter next) {
    HapticFeedback.selectionClick();
    setState(() => _draft = next);
  }

  void _setType(TransactionType? type, Map<String, TransactionCategory> cats) {
    final keep = type == null
        ? _draft.categoryIds
        : _draft.categoryIds
              .where((id) => cats[id] == null || cats[id]!.type == type)
              .toSet();
    _set(_draft.copyWith(type: () => type, categoryIds: keep));
  }

  void _reset() => _set(
    _draft.copyWith(
      type: () => null,
      categoryIds: const {},
      amount: () => null,
      accountIds: const {},
      channels: const {},
      origins: const {},
    ),
  );

  /// Channels worth filtering by: suggestions that are in use, custom ones
  /// in use, and anything already selected. Most used first.
  List<String> _channelOptions(List<Transaction> txs, List<Transfer> transfers, Set<String> selected) {
    final uses = <String, int>{};
    void add(String? raw) {
      final v = cleanChannel(raw);
      if (v == null) return;
      final key = uses.keys.firstWhere((k) => k.toLowerCase() == v.toLowerCase(), orElse: () => v);
      uses[key] = (uses[key] ?? 0) + 1;
    }

    for (final t in txs) {
      add(t.channel);
    }
    for (final t in transfers) {
      add(t.channel);
    }
    for (final s in selected) {
      uses.putIfAbsent(s, () => 0);
    }
    final list = uses.keys.toList()
      ..sort((a, b) {
        final u = uses[b]!.compareTo(uses[a]!);
        return u != 0 ? u : a.toLowerCase().compareTo(b.toLowerCase());
      });
    return list;
  }

  Set<T> _toggled<T>(Set<T> set, T value) {
    final next = Set<T>.of(set);
    if (!next.remove(value)) next.add(value);
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final txs =
        ref.watch(sortedTransactionsProvider).value ?? const <Transaction>[];
    final cats =
        ref.watch(categoriesByIdProvider).value ??
        const <String, TransactionCategory>{};
    final range = _draft.range;
    // Transactions of the period and type: what the amount + category
    // pickers describe.
    final inPeriod = [
      for (final t in txs)
        if (range.contains(t.date) &&
            (_draft.type == null || t.type == _draft.type))
          t,
    ];
    final transfers = ref.watch(transfersProvider).value ?? const <Transfer>[];
    final accountsById = {
      for (final a in ref.watch(moneyAccountsProvider).value ?? const <MoneyAccount>[]) a.id: a,
    };
    final matches =
        TransactionQuery.count(txs, _draft, cats) +
        transfers.where((t) => range.contains(t.date) && TransactionQuery.passesTransfer(t, _draft, accountsById)).length;
    final channelOptions = _channelOptions(txs, transfers, _draft.channels);
    final active = _draft.advancedCount + (_draft.type != null ? 1 : 0);

    return FinnSheetScaffold(
      title: 'Filters',
      footer: Row(
        children: [
          LedgerButton(
            label: 'Reset',
            variant: LedgerButtonVariant.quiet,
            onPressed: active == 0 ? null : _reset,
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: LedgerButton(
              key: const ValueKey('activity-filter-apply'),
              label: matches == 0
                  ? 'No matches'
                  : 'Show $matches transaction${matches == 1 ? '' : 's'}',
              expand: true,
              onPressed: () => Navigator.of(context).pop(_draft),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerSegmented<TransactionType?>(
            segments: const [
              LedgerSegment(null, 'All'),
              LedgerSegment(TransactionType.income, 'Income'),
              LedgerSegment(TransactionType.expense, 'Expense'),
            ],
            selected: _draft.type,
            onChanged: (t) => _setType(t, cats),
          ),
          _Group(
            title: 'Amount',
            trailing: amountRangeLabel(_draft.amount),
            child: _AmountPicker(
              amounts: [for (final t in inPeriod) t.amount.paise],
              value: _draft.amount,
              onChanged: (r) => setState(
                () => _draft = _draft.copyWith(
                  amount: () => r == null || r.isOpen ? null : r,
                ),
              ),
              onPreset: (r) => _set(_draft.copyWith(amount: () => r)),
            ),
          ),
          _Group(
            title: 'Category',
            trailing: _draft.categoryIds.isEmpty
                ? 'All'
                : '${_draft.categoryIds.length} selected',
            child: _categoryChips(inPeriod, cats),
          ),
          _Group(
            title: 'Account',
            trailing: _draft.accountIds.isEmpty
                ? 'Any'
                : '${_draft.accountIds.length} selected',
            child: Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [
                for (final a in ref.watch(moneyAccountsProvider).value ?? const <MoneyAccount>[])
                  LedgerChip(
                    key: ValueKey('filter-account:${a.id}'),
                    label: a.name,
                    icon: accountIcon(a.kind),
                    selected: _draft.accountIds.contains(a.id),
                    onTap: () => _set(
                      _draft.copyWith(accountIds: _toggled(_draft.accountIds, a.id)),
                    ),
                  ),
              ],
            ),
          ),
          if (channelOptions.isNotEmpty)
            _Group(
              title: 'Channel',
              trailing: _draft.channels.isEmpty ? 'Any' : '${_draft.channels.length} selected',
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final ch in channelOptions)
                    LedgerChip(
                      key: ValueKey('filter-channel:$ch'),
                      label: ch,
                      selected: _draft.channels.contains(ch),
                      onTap: () => _set(_draft.copyWith(channels: _toggled(_draft.channels, ch))),
                    ),
                ],
              ),
            ),
          _Group(
            title: 'Source',
            trailing: _draft.origins.isEmpty
                ? 'Any'
                : '${_draft.origins.length} selected',
            child: Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [
                for (final o in TransactionOrigin.values)
                  LedgerChip(
                    key: ValueKey('filter-origin:${o.name}'),
                    label: originLabel(o),
                    selected: _draft.origins.contains(o),
                    onTap: () => _set(
                      _draft.copyWith(origins: _toggled(_draft.origins, o)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Most-used categories first; only [_visibleCategories] until "View all".
  Widget _categoryChips(
    List<Transaction> inPeriod,
    Map<String, TransactionCategory> cats,
  ) {
    final uses = <String, int>{};
    for (final t in inPeriod) {
      uses[t.categoryId] = (uses[t.categoryId] ?? 0) + 1;
    }
    final list =
        cats.values
            .where(
              (c) =>
                  (_draft.type == null || c.type == _draft.type) &&
                  (!c.isArchived || uses.containsKey(c.id)),
            )
            .toList()
          ..sort((a, b) {
            final u = (uses[b.id] ?? 0).compareTo(uses[a.id] ?? 0);
            return u != 0
                ? u
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    final shown = _allCategories
        ? list
        : [
            ...list.take(_visibleCategories),
            // Selected ones always stay visible.
            ...list
                .skip(_visibleCategories)
                .where((c) => _draft.categoryIds.contains(c.id)),
          ];
    final hiddenCount = list.length - shown.length;
    return MotionAnimatedSize(
      child: Wrap(
        spacing: Sp.sm,
        runSpacing: Sp.sm,
        children: [
          for (final cat in shown)
            LedgerChip(
              key: ValueKey('filter-category:${cat.id}'),
              label: cat.name,
              icon: CategoryIcons.of(cat.iconKey),
              count: uses[cat.id],
              selected: _draft.categoryIds.contains(cat.id),
              onTap: () => _set(
                _draft.copyWith(
                  categoryIds: _toggled(_draft.categoryIds, cat.id),
                ),
              ),
            ),
          if (hiddenCount > 0 ||
              _allCategories && list.length > _visibleCategories)
            LedgerChip(
              key: const ValueKey('filter-category-more'),
              label: _allCategories ? 'Show less' : 'View all · +$hiddenCount',
              onTap: () => setState(() => _allCategories = !_allCategories),
            ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.child, this.trailing});

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(top: LedgerForm.groupGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: t.bodyStrong),
                ),
              ),
              if (trailing != null)
                Text(trailing!, style: t.label.copyWith(color: c.inkSoft)),
            ],
          ),
          const SizedBox(height: Sp.md),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Amount: presets + histogram + range slider
// ---------------------------------------------------------------------------

/// Slider runs on a square-root scale so small, everyday amounts get most of
/// the track while a rare large payment stays reachable.
class _AmountScale {
  _AmountScale(List<int> amounts)
    : maxRupees = _niceCeil(amounts.fold<int>(0, math.max) / 100);

  final int maxRupees;

  static int _niceCeil(double v) {
    if (v <= 1000) return 1000;
    final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in const [1, 2, 2.5, 5, 10]) {
      if (v <= m * mag) return (m * mag).round();
    }
    return (10 * mag).round();
  }

  int rupeesAt(double s) => _snap(maxRupees * s * s);

  double positionOf(int rupees) =>
      math.sqrt((rupees / maxRupees).clamp(0.0, 1.0));

  static int _snap(double r) {
    final step = r < 1000 ? 50 : (r < 10000 ? 250 : (r < 100000 ? 1000 : 5000));
    return (r / step).round() * step;
  }
}

class _AmountPicker extends StatelessWidget {
  const _AmountPicker({
    required this.amounts,
    required this.value,
    required this.onChanged,
    required this.onPreset,
  });

  final List<int> amounts;
  final AmountRange? value;
  final ValueChanged<AmountRange?> onChanged;
  final ValueChanged<AmountRange?> onPreset;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final scale = _AmountScale(amounts);
    final lo = value?.minPaise == null
        ? 0.0
        : scale.positionOf(value!.minPaise! ~/ 100);
    final hi = value?.maxPaise == null
        ? 1.0
        : scale.positionOf(value!.maxPaise! ~/ 100);
    const bins = 28;
    final counts = List<int>.filled(bins, 0);
    for (final p in amounts) {
      final s = scale.positionOf(p ~/ 100);
      counts[(s * bins).floor().clamp(0, bins - 1)]++;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Sp.sm,
          runSpacing: Sp.sm,
          children: [
            for (final (min, max) in _amountPresets)
              Builder(
                builder: (context) {
                  final r = AmountRange(
                    minPaise: min == null ? null : min * 100,
                    maxPaise: max == null ? null : max * 100,
                  );
                  final on = value == r;
                  return LedgerChip(
                    key: ValueKey('filter-amount:${min ?? 0}-${max ?? 'up'}'),
                    label: amountRangeLabel(r),
                    selected: on,
                    onTap: () => onPreset(on ? null : r),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: Sp.md),
        // Where this period's transactions sit; bars inside the range light up.
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md),
            child: CustomPaint(
              size: const Size(double.infinity, 36),
              painter: _HistogramPainter(
                counts: counts,
                lo: lo,
                hi: hi,
                grow: 1,
                on: c.ink,
                off: c.line,
              ),
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            rangeThumbShape: const RoundRangeSliderThumbShape(
              enabledThumbRadius: 9,
            ),
            showValueIndicator: ShowValueIndicator.onDrag,
          ),
          child: RangeSlider(
            values: RangeValues(lo, hi),
            activeColor: c.ink,
            inactiveColor: c.sunken,
            labels: RangeLabels(
              lo <= 0
                  ? '₹0'
                  : MoneyFormatter.compact(Money.rupees(scale.rupeesAt(lo))),
              hi >= 1
                  ? 'Max'
                  : MoneyFormatter.compact(Money.rupees(scale.rupeesAt(hi))),
            ),
            onChanged: (v) {
              final min = v.start <= 0.001
                  ? null
                  : scale.rupeesAt(v.start) * 100;
              final max = v.end >= 0.999 ? null : scale.rupeesAt(v.end) * 100;
              if (min != null && max != null && min > max) return;
              final next = AmountRange(minPaise: min, maxPaise: max);
              if (next != value) {
                HapticFeedback.selectionClick();
                onChanged(next);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
          child: Row(
            children: [
              Text('₹0', style: context.type.small.copyWith(color: c.inkFaint)),
              const Spacer(),
              Text(
                MoneyFormatter.compact(Money.rupees(scale.maxRupees)),
                style: context.type.small.copyWith(color: c.inkFaint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter({
    required this.counts,
    required this.lo,
    required this.hi,
    required this.grow,
    required this.on,
    required this.off,
  });

  final List<int> counts;
  final double lo;
  final double hi;
  final double grow;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final n = counts.length;
    final maxC = counts.fold<int>(0, math.max);
    final slot = size.width / n;
    final p = Paint();
    for (var i = 0; i < n; i++) {
      final mid = (i + 0.5) / n;
      final inside = mid >= lo && mid <= hi;
      final h = maxC == 0 || counts[i] == 0
          ? 2.0
          : math.max(3.0, size.height * counts[i] / maxC * grow);
      p.color = inside
          ? on.withValues(alpha: counts[i] == 0 ? 0.3 : 0.85)
          : off;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(i * slot + 1, size.height - h, slot - 2, h),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_HistogramPainter old) =>
      old.grow != grow ||
      old.lo != lo ||
      old.hi != hi ||
      old.counts != counts ||
      old.on != on;
}
