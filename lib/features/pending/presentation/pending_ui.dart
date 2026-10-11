import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/pending_payment.dart';

/// Presentation helpers for [PendingDirection]: never colour alone — every
/// direction also has an icon and a plain-language label.
extension PendingDirectionUi on PendingDirection {
  bool get isOwe => this == PendingDirection.iOwe;

  IconData get icon => isOwe ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft;

  Color color(FinnColors c) => isOwe ? c.negative : c.positive;

  Color soft(FinnColors c) => isOwe ? c.negativeSoft : c.positiveSoft;

  /// "You owe Rahul" / "Priya owes you".
  String sentence(String who) => isOwe ? 'You owe $who' : '$who owes you';
}

// ---------------------------------------------------------------------------
// Filtering (pure presentation state, derived once per filter in a provider).
// ---------------------------------------------------------------------------

enum PendingTab {
  active('Active'),
  settled('Settled'),
  writtenOff('Written off');

  const PendingTab(this.label);
  final String label;

  bool matches(PendingStatus s) => switch (this) {
        PendingTab.active => s.isActive,
        PendingTab.settled => s == PendingStatus.settled,
        PendingTab.writtenOff => s == PendingStatus.cancelled,
      };
}

@immutable
class PendingFilter {
  const PendingFilter({this.tab = PendingTab.active, this.direction, this.query = ''});

  final PendingTab tab;

  /// Null shows both directions.
  final PendingDirection? direction;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is PendingFilter && other.tab == tab && other.direction == direction && other.query == query;

  @override
  int get hashCode => Object.hash(tab, direction, query);
}

/// A row in the pending list: either a person header or an item.
sealed class PendingEntry {
  const PendingEntry();
}

final class PendingPersonHeader extends PendingEntry {
  const PendingPersonHeader({required this.name, required this.count, required this.toPay, required this.toCollect});
  final String name;
  final int count;
  final Money toPay;
  final Money toCollect;
}

final class PendingItemEntry extends PendingEntry {
  const PendingItemEntry(this.view, {this.grouped = false});
  final PendingView view;

  /// Shown under a [PendingPersonHeader].
  final bool grouped;
}

/// Items for the current filter, grouped by counterparty when several items
/// share a person (each item stays separate — never merged).
List<PendingEntry> buildPendingEntries(List<PendingView> all, PendingFilter f) {
  final q = f.query.trim().toLowerCase();
  final items = all.where((v) {
    if (!f.tab.matches(v.status)) return false;
    if (f.direction != null && v.payment.direction != f.direction) return false;
    if (q.isEmpty) return true;
    final p = v.payment;
    return p.counterparty.toLowerCase().contains(q) ||
        p.purpose.toLowerCase().contains(q) ||
        (p.notes?.toLowerCase().contains(q) ?? false);
  }).toList()
    ..sort((a, b) => _compare(a, b, f.tab));

  final groups = <String, List<PendingView>>{};
  for (final v in items) {
    groups.putIfAbsent(v.payment.counterparty.trim().toLowerCase(), () => []).add(v);
  }
  final entries = <PendingEntry>[];
  for (final g in groups.values) {
    if (g.length == 1) {
      entries.add(PendingItemEntry(g.single));
      continue;
    }
    entries.add(PendingPersonHeader(
      name: g.first.payment.counterparty,
      count: g.length,
      toPay: Money.sum(g.where((v) => v.payment.direction.isOwe).map((v) => v.outstanding)),
      toCollect: Money.sum(g.where((v) => !v.payment.direction.isOwe).map((v) => v.outstanding)),
    ));
    entries.addAll(g.map((v) => PendingItemEntry(v, grouped: true)));
  }
  return entries;
}

int _compare(PendingView a, PendingView b, PendingTab tab) {
  switch (tab) {
    case PendingTab.active:
      if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
      final ad = a.payment.dueDate, bd = b.payment.dueDate;
      if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
      if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
      return b.payment.createdDate.compareTo(a.payment.createdDate);
    case PendingTab.settled:
      return (b.settledOn ?? b.payment.updatedAt).compareTo(a.settledOn ?? a.payment.updatedAt);
    case PendingTab.writtenOff:
      return b.payment.updatedAt.compareTo(a.payment.updatedAt);
  }
}

final pendingEntriesProvider = Provider.family<AsyncValue<List<PendingEntry>>, PendingFilter>(
  (ref, f) => ref.watch(pendingViewsProvider).whenData((all) => buildPendingEntries(all, f)),
);

/// Headline numbers for the pending screen.
@immutable
class PendingOverview {
  const PendingOverview({
    required this.toPay,
    required this.toCollect,
    required this.payCount,
    required this.collectCount,
    required this.overdueCount,
    required this.overdueToPay,
    required this.overdueToCollect,
    required this.counts,
  });

  factory PendingOverview.of(List<PendingView> all) {
    final active = all.where((v) => v.status.isActive).toList();
    final owe = active.where((v) => v.payment.direction.isOwe);
    final collect = active.where((v) => !v.payment.direction.isOwe);
    final overdue = active.where((v) => v.isOverdue).toList();
    return PendingOverview(
      toPay: Money.sum(owe.map((v) => v.outstanding)),
      toCollect: Money.sum(collect.map((v) => v.outstanding)),
      payCount: owe.length,
      collectCount: collect.length,
      overdueCount: overdue.length,
      overdueToPay: Money.sum(overdue.where((v) => v.payment.direction.isOwe).map((v) => v.outstanding)),
      overdueToCollect: Money.sum(overdue.where((v) => !v.payment.direction.isOwe).map((v) => v.outstanding)),
      counts: {for (final t in PendingTab.values) t: all.where((v) => t.matches(v.status)).length},
    );
  }

  final Money toPay;
  final Money toCollect;
  final int payCount;
  final int collectCount;
  final int overdueCount;
  final Money overdueToPay;
  final Money overdueToCollect;
  final Map<PendingTab, int> counts;

  @override
  bool operator ==(Object other) =>
      other is PendingOverview &&
      other.toPay == toPay &&
      other.toCollect == toCollect &&
      other.overdueCount == overdueCount &&
      other.overdueToPay == overdueToPay &&
      other.overdueToCollect == overdueToCollect &&
      other.counts.length == counts.length &&
      PendingTab.values.every((t) => other.counts[t] == counts[t]);

  @override
  int get hashCode => Object.hash(toPay, toCollect, overdueCount, overdueToPay, overdueToCollect,
      Object.hashAll(PendingTab.values.map((t) => counts[t])));
}

final pendingOverviewProvider = Provider<AsyncValue<PendingOverview>>(
  (ref) => ref.watch(pendingViewsProvider).whenData(PendingOverview.of),
);

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// Due / status chip for a pending item (icon + text, not colour only).
class PendingDueChip extends StatelessWidget {
  const PendingDueChip({super.key, required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final due = view.payment.dueDate;
    switch (view.status) {
      case PendingStatus.settled:
        final on = view.settledOn;
        return StatusPill(
          label: on == null ? 'Settled' : 'Settled ${DateFormats.dayMonth.format(on)}',
          color: c.positive,
          icon: LucideIcons.circleCheck,
        );
      case PendingStatus.cancelled:
        return StatusPill(label: 'Written off', color: c.textSecondary, icon: LucideIcons.ban);
      case PendingStatus.open || PendingStatus.partiallySettled:
        if (due == null) return StatusPill(label: 'No due date', color: c.textSecondary, icon: LucideIcons.calendar);
        final days = view.daysUntilDue!;
        if (days < 0) {
          return StatusPill(
            label: 'Overdue ${-days} ${-days == 1 ? 'day' : 'days'}',
            color: c.negative,
            icon: LucideIcons.triangleAlert,
          );
        }
        if (days == 0) return StatusPill(label: 'Due today', color: c.attention, icon: LucideIcons.clock);
        if (days <= 7) {
          return StatusPill(
              label: days == 1 ? 'Due tomorrow' : 'Due in $days days', color: c.warning, icon: LucideIcons.clock);
        }
        return StatusPill(
          label: 'Due ${DateFormats.dayMonth.format(due)}',
          color: c.textSecondary,
          icon: LucideIcons.calendar,
        );
    }
  }
}

/// Small label showing who pays whom.
class PendingDirectionLabel extends StatelessWidget {
  const PendingDirectionLabel({super.key, required this.direction, this.onGradient = false});

  final PendingDirection direction;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = onGradient ? Colors.white : direction.color(c);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(direction.icon, size: 13, color: color),
        const SizedBox(width: Space.x1),
        Flexible(
          child: Text(
            direction.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.micro.copyWith(color: color, fontWeight: FontWeight.w900, letterSpacing: 0.6),
          ),
        ),
      ],
    );
  }
}

/// One pending item in a list.
class PendingCard extends StatelessWidget {
  const PendingCard({super.key, required this.view, required this.onTap, this.onSettle, this.compact = false});

  final PendingView view;
  final VoidCallback onTap;
  final VoidCallback? onSettle;

  /// Hides the counterparty (shown in a group header above).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final p = view.payment;
    final dir = p.direction;
    final active = view.status.isActive;
    final partial = view.status == PendingStatus.partiallySettled;
    final accent = active ? dir.color(c) : c.borderStrong;
    final shown = active ? view.outstanding : p.originalAmount;
    final semantics = '${dir.sentence(p.counterparty)} ${MoneyFormatter.spoken(shown)} for ${p.purpose}. '
        '${view.status.label}${view.isOverdue ? ', overdue' : ''}';
    return FinnCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      semanticLabel: semantics,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 4))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, Space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconTile(
                    icon: active ? dir.icon : (view.status == PendingStatus.settled ? LucideIcons.circleCheck : LucideIcons.ban),
                    background: active ? dir.soft(c) : c.surfaceMuted,
                    foreground: active ? dir.color(c) : c.textSecondary,
                    size: 40,
                    radius: Radii.lg,
                    iconSize: 20,
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(compact ? p.purpose : p.counterparty,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong),
                        const SizedBox(height: 2),
                        Text(
                          compact ? p.kind.label : '${p.purpose} · ${p.kind.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AmountText(shown, style: t.amountMedium.copyWith(color: active ? dir.color(c) : c.textSecondary)),
                      if (partial) ...[
                        const SizedBox(height: 2),
                        Text('of ${p.originalAmount.format()}', style: t.micro),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Space.x2),
              Row(
                children: [
                  const SizedBox(width: 40 + Space.x3),
                  Expanded(child: PendingDirectionLabel(direction: dir)),
                  const SizedBox(width: Space.x2),
                  Flexible(child: PendingDueChip(view: view)),
                ],
              ),
              if (partial) ...[
                const SizedBox(height: Space.x3),
                FinnProgressBar(
                  value: view.settledBps / 10000,
                  height: 6,
                  color: dir.color(c),
                  semanticsLabel: 'Settled so far',
                ),
                const SizedBox(height: Space.x1),
                Text('${view.settled.format()} settled · ${view.outstanding.format()} left', style: t.micro),
              ],
              if (active && onSettle != null) ...[
                const SizedBox(height: Space.x3),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FinnButton(
                    label: dir.isOwe ? 'Settle · I paid' : 'Settle · I received',
                    icon: LucideIcons.circleCheck,
                    size: FinnButtonSize.sm,
                    variant: FinnButtonVariant.secondary,
                    onPressed: onSettle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-select payment method chips.
class PendingMethodChips extends StatelessWidget {
  const PendingMethodChips({super.key, required this.selected, required this.onChanged});

  final PaymentMethod? selected;
  final ValueChanged<PaymentMethod> onChanged;

  static const _icons = {
    PaymentMethod.upi: LucideIcons.smartphone,
    PaymentMethod.card: LucideIcons.creditCard,
    PaymentMethod.cash: LucideIcons.banknote,
    PaymentMethod.bankTransfer: LucideIcons.landmark,
    PaymentMethod.wallet: LucideIcons.wallet,
    PaymentMethod.other: LucideIcons.circleDot,
  };

  @override
  Widget build(BuildContext context) => FilterChipBar<PaymentMethod>(
        padding: EdgeInsets.zero,
        multiSelect: false,
        items: [for (final m in PaymentMethod.values) FilterChipItem(m, m.label, icon: _icons[m])],
        selected: {?selected},
        onChanged: (s) => onChanged(s.first),
      );
}

/// Label above a non-text form control.
class PendingFieldLabel extends StatelessWidget {
  const PendingFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.x1_5),
        child: Text(text, style: context.text.label),
      );
}
