
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../domain/pending_payment.dart';

/// Presentation helpers for [PendingDirection]: never colour alone — every
/// direction also has an icon and a plain-language label.
extension PendingDirectionUi on PendingDirection {
  bool get isOwe => this == PendingDirection.iOwe;

  IconData get icon =>
      isOwe ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft;

  /// "You owe Rahul" / "Priya owes you".
  String sentence(String who) => isOwe ? 'You owe $who' : '$who owes you';
}

// ---------------------------------------------------------------------------
// Filtering and sorting (pure presentation state, derived once per filter in
// a provider).
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

/// List order. Pending items have no deadline, so [waiting] (the default)
/// puts the oldest open items first: the people to ask (or pay) first.
enum PendingSort {
  waiting('Waiting longest', LucideIcons.hourglass),
  amount('Largest amount', LucideIcons.arrowDownWideNarrow),
  newest('Recently added', LucideIcons.sparkles),
  name('Name A–Z', LucideIcons.arrowDownAZ);

  const PendingSort(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// How long an item has been open. Informative only — never "late".
enum PendingAge {
  fresh('Under a week', LucideIcons.sprout),
  weeks('1–3 weeks', LucideIcons.calendarDays),
  long('Over 3 weeks', LucideIcons.hourglass);

  const PendingAge(this.label, this.icon);
  final String label;
  final IconData icon;

  static PendingAge of(PendingView v) {
    final d = v.daysOpen;
    if (d <= 7) return PendingAge.fresh;
    if (d <= PendingView.longPendingDays) return PendingAge.weeks;
    return PendingAge.long;
  }
}

@immutable
class PendingFilter {
  const PendingFilter({
    this.tab = PendingTab.active,
    this.direction,
    this.query = '',
    this.sort = PendingSort.waiting,
    this.ages = const {},
    this.kinds = const {},
    this.groupByPerson = true,
  });

  final PendingTab tab;

  /// Null shows both directions.
  final PendingDirection? direction;
  final String query;
  final PendingSort sort;

  /// Empty means any age.
  final Set<PendingAge> ages;

  /// Empty means every reason.
  final Set<PendingKind> kinds;

  /// Several items with one person share a card.
  final bool groupByPerson;

  /// Filters beyond tab, search and sort; drives the badge on the
  /// options button.
  int get activeCount =>
      (direction != null ? 1 : 0) + ages.length + kinds.length;

  PendingFilter copyWith({
    PendingTab? tab,
    PendingDirection? Function()? direction,
    String? query,
    PendingSort? sort,
    Set<PendingAge>? ages,
    Set<PendingKind>? kinds,
    bool? groupByPerson,
  }) => PendingFilter(
    tab: tab ?? this.tab,
    direction: direction != null ? direction() : this.direction,
    query: query ?? this.query,
    sort: sort ?? this.sort,
    ages: ages ?? this.ages,
    kinds: kinds ?? this.kinds,
    groupByPerson: groupByPerson ?? this.groupByPerson,
  );

  /// Same tab, search and sort with every filter cleared.
  PendingFilter cleared() => PendingFilter(
    tab: tab,
    query: query,
    sort: sort,
    groupByPerson: groupByPerson,
  );

  bool accepts(PendingView v) {
    if (!tab.matches(v.status)) return false;
    final p = v.payment;
    if (direction != null && p.direction != direction) return false;
    if (ages.isNotEmpty && !ages.contains(PendingAge.of(v))) return false;
    if (kinds.isNotEmpty && !kinds.contains(p.kind)) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return p.counterparty.toLowerCase().contains(q) ||
        p.purpose.toLowerCase().contains(q) ||
        (p.notes?.toLowerCase().contains(q) ?? false);
  }

  @override
  bool operator ==(Object other) =>
      other is PendingFilter &&
      other.tab == tab &&
      other.direction == direction &&
      other.query == query &&
      other.sort == sort &&
      setEquals(other.ages, ages) &&
      setEquals(other.kinds, kinds) &&
      other.groupByPerson == groupByPerson;

  @override
  int get hashCode => Object.hash(
    tab,
    direction,
    query,
    sort,
    Object.hashAllUnordered(ages),
    Object.hashAllUnordered(kinds),
    groupByPerson,
  );
}

/// A row in the pending list: one item, or several items with one person.
sealed class PendingEntry {
  const PendingEntry();
}

final class PendingPersonGroup extends PendingEntry {
  const PendingPersonGroup({
    required this.name,
    required this.items,
    required this.toPay,
    required this.toCollect,
  });
  final String name;
  final List<PendingView> items;
  final Money toPay;
  final Money toCollect;

  int get count => items.length;
}

final class PendingItemEntry extends PendingEntry {
  const PendingItemEntry(this.view);
  final PendingView view;
}

/// One bill split between several people: entered once, so it reads as
/// one entry. [items] are the people shown under the current filter;
/// [split] holds every person, for the bill totals.
final class PendingSplitEntry extends PendingEntry {
  const PendingSplitEntry({required this.split, required this.items});
  final PendingSplitView split;
  final List<PendingView> items;

  int get count => items.length;
}

/// Rows an entry stands for.
int pendingEntryCount(PendingEntry e) => switch (e) {
  PendingItemEntry() => 1,
  PendingPersonGroup(:final count) || PendingSplitEntry(:final count) => count,
};

/// Every split in [pendingViewsProvider], by split id.
final pendingSplitsProvider = Provider<Map<String, PendingSplitView>>(
  (ref) => PendingSplitView.collect(
    ref.watch(pendingViewsProvider).value ?? const [],
  ),
);

/// Items matching [f], in its sort order.
List<PendingView> filterPending(List<PendingView> all, PendingFilter f) =>
    all.where(f.accepts).toList()..sort((a, b) => _compare(a, b, f));

/// Items for the current filter. People of one split always sit together
/// as one entry (when two or more of them match). When
/// [PendingFilter.groupByPerson] is on, the other items that share a person
/// sit together too (each item stays separate — never merged). A group
/// ranks where its first item does.
List<PendingEntry> buildPendingEntries(List<PendingView> all, PendingFilter f) {
  final items = filterPending(all, f);
  final splitCounts = <String, int>{};
  for (final v in items) {
    if (v.payment.split case final s?)
      splitCounts[s.id] = (splitCounts[s.id] ?? 0) + 1;
  }
  final groups = <String, List<PendingView>>{};
  for (final v in items) {
    final s = v.payment.split;
    final key = s != null && splitCounts[s.id]! > 1
        ? 'split:${s.id}'
        : (f.groupByPerson
              ? 'person:${v.payment.counterparty.trim().toLowerCase()}'
              : 'item:${v.payment.id}');
    groups.putIfAbsent(key, () => []).add(v);
  }
  final splits = groups.keys.any((k) => k.startsWith('split:'))
      ? PendingSplitView.collect(all)
      : const <String, PendingSplitView>{};
  return [
    for (final MapEntry(:key, value: g) in groups.entries)
      if (key.startsWith('split:'))
        PendingSplitEntry(
          split: splits[key.substring(6)]!,
          // People in the order they were added, like the bill.
          items: [
            for (final m in splits[key.substring(6)]!.members)
              if (g.contains(m)) m,
          ],
        )
      else if (g.length == 1)
        PendingItemEntry(g.single)
      else
        PendingPersonGroup(
          name: g.first.payment.counterparty,
          items: g,
          toPay: Money.sum(
            g.where((v) => v.payment.direction.isOwe).map((v) => v.outstanding),
          ),
          toCollect: Money.sum(
            g
                .where((v) => !v.payment.direction.isOwe)
                .map((v) => v.outstanding),
          ),
        ),
  ];
}

/// Amount a row shows: what is left while active, else the original.
Money pendingShownAmount(PendingView v) =>
    v.status.isActive ? v.outstanding : v.payment.originalAmount;

int _compare(PendingView a, PendingView b, PendingFilter f) {
  final pa = a.payment, pb = b.payment;
  final int r = switch (f.sort) {
    PendingSort.waiting => switch (f.tab) {
      PendingTab.active => () {
        final age = pa.createdDate.compareTo(pb.createdDate);
        return age != 0
            ? age
            : pendingShownAmount(b).compareTo(pendingShownAmount(a));
      }(),
      PendingTab.settled => (b.settledOn ?? pb.updatedAt).compareTo(
        a.settledOn ?? pa.updatedAt,
      ),
      PendingTab.writtenOff => pb.updatedAt.compareTo(pa.updatedAt),
    },
    PendingSort.amount => pendingShownAmount(
      b,
    ).compareTo(pendingShownAmount(a)),
    PendingSort.newest => pb.createdDate.compareTo(pa.createdDate),
    PendingSort.name => pa.counterparty.toLowerCase().compareTo(
      pb.counterparty.toLowerCase(),
    ),
  };
  return r != 0
      ? r
      : pa.purpose.toLowerCase().compareTo(pb.purpose.toLowerCase());
}

final pendingEntriesProvider =
    Provider.family<AsyncValue<List<PendingEntry>>, PendingFilter>(
      (ref, f) => ref
          .watch(pendingViewsProvider)
          .whenData((all) => buildPendingEntries(all, f)),
    );

/// Headline numbers for the pending screen.
@immutable
class PendingOverview {
  const PendingOverview({
    required this.toPay,
    required this.toCollect,
    required this.payCount,
    required this.collectCount,
    required this.longToPay,
    required this.longToCollect,
    required this.longCount,
    required this.people,
    required this.oldest,
    required this.counts,
  });

  factory PendingOverview.of(List<PendingView> all) {
    final active = all.where((v) => v.status.isActive).toList();
    final owe = active.where((v) => v.payment.direction.isOwe);
    final collect = active.where((v) => !v.payment.direction.isOwe);
    final long = active.where((v) => v.isLongPending).toList();
    return PendingOverview(
      toPay: Money.sum(owe.map((v) => v.outstanding)),
      toCollect: Money.sum(collect.map((v) => v.outstanding)),
      payCount: owe.length,
      collectCount: collect.length,
      longToPay: Money.sum(
        long.where((v) => v.payment.direction.isOwe).map((v) => v.outstanding),
      ),
      longToCollect: Money.sum(
        long.where((v) => !v.payment.direction.isOwe).map((v) => v.outstanding),
      ),
      longCount: long.length,
      people: active
          .map((v) => v.payment.counterparty.trim().toLowerCase())
          .toSet()
          .length,
      oldest: (List.of(
        active,
      )..sort((a, b) => b.daysOpen.compareTo(a.daysOpen))).take(3).toList(),
      counts: {
        for (final t in PendingTab.values)
          t: all.where((v) => t.matches(v.status)).length,
      },
    );
  }

  final Money toPay;
  final Money toCollect;
  final int payCount;
  final int collectCount;

  /// Outstanding on items open longer than [PendingView.longPendingDays].
  final Money longToPay;
  final Money longToCollect;
  final int longCount;

  /// Distinct people with active items.
  final int people;

  /// Active items waiting longest, oldest first (up to 3): whom to ask or
  /// pay first.
  final List<PendingView> oldest;
  final Map<PendingTab, int> counts;

  /// Positive: more is coming back to the user than going out.
  Money get net => toCollect - toPay;

  int get activeCount => payCount + collectCount;

  @override
  bool operator ==(Object other) =>
      other is PendingOverview &&
      other.toPay == toPay &&
      other.toCollect == toCollect &&
      other.payCount == payCount &&
      other.collectCount == collectCount &&
      other.longToPay == longToPay &&
      other.longToCollect == longToCollect &&
      other.longCount == longCount &&
      other.people == people &&
      listEquals(other.oldest, oldest) &&
      PendingTab.values.every((t) => other.counts[t] == counts[t]);

  @override
  int get hashCode => Object.hash(
    toPay,
    toCollect,
    payCount,
    collectCount,
    longToPay,
    longToCollect,
    longCount,
    people,
    Object.hashAll(oldest),
    Object.hashAll(PendingTab.values.map((t) => counts[t])),
  );
}

final pendingOverviewProvider = Provider<AsyncValue<PendingOverview>>(
  (ref) => ref.watch(pendingViewsProvider).whenData(PendingOverview.of),
);

// ---------------------------------------------------------------------------
// Shared behaviour
// ---------------------------------------------------------------------------

/// "40 days", "1 day", "Today".
String pendingDays(int days) =>
    days <= 0 ? 'Today' : '$days ${days == 1 ? 'day' : 'days'}';

/// Plain, informative status: "Ramesh has not returned your money · 40 days
/// have passed" / "You have not paid Rahul back · 24 days have passed".
String pendingAgeSentence(PendingView v) {
  final who = v.payment.counterparty;
  final d = v.daysOpen;
  final passed = d <= 0
      ? 'Started today'
      : '$d ${d == 1 ? 'day has' : 'days have'} passed';
  return v.payment.direction.isOwe
      ? 'You have not paid $who back yet. $passed.'
      : '$who has not returned your money yet. $passed.';
}

/// Opens the share sheet with a polite reminder for money owed to the user.
Future<void> sharePendingReminder(BuildContext context, PendingView v) {
  final p = v.payment;
  final since = v.daysOpen > 1 ? ' from ${v.daysOpen} days ago' : '';
  final text =
      'Hi ${p.counterparty.split(' ').first}, a gentle reminder about '
      '${MoneyFormatter.format(v.outstanding, decimals: DecimalDisplay.none)} for ${p.purpose}$since. Thanks!';
  final box = context.findRenderObject() as RenderBox?;
  return SharePlus.instance.share(
    ShareParams(
      text: text,
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// "PN" for "Priya Nair", "S" for "Society".
String pendingInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  if (parts.length == 1) return first.toUpperCase();
  return (first + parts.last.characters.first).toUpperCase();
}
// ---------------------------------------------------------------------------
// List widgets ("calm ledger" kit)
// ---------------------------------------------------------------------------

/// Whole-rupee money for sentences, masked when balances are hidden.
String pendingMoney(BuildContext context, Money m) =>
    AmountVisibility.hiddenOf(context)
    ? MoneyFormatter.masked
    : MoneyFormatter.format(m, decimals: DecimalDisplay.none);

/// Spoken amount for semantics that respects hidden balances.
String pendingSpoken(BuildContext context, Money m) =>
    AmountVisibility.hiddenOf(context)
    ? 'an amount'
    : AmountText.spokenLabel(m);

/// Row amount colour: green for money coming back, ink for money going
/// out, soft once the item is closed.
Color pendingAmountColor(
  BuildContext context,
  PendingDirection d, {
  bool active = true,
}) {
  final c = context.ink;
  if (!active) return c.inkSoft;
  return d.isOwe ? c.ink : c.green;
}

/// "to get" / "to pay": the word under an amount, so direction never rests
/// on colour alone.
String pendingSideLabel(PendingDirection d) => d.isOwe ? 'to pay' : 'to get';

/// A person's initials in a round well. [shared] adds a small link mark:
/// the item also lives in that person's FiNN.
class PendingInitials extends StatelessWidget {
  const PendingInitials({
    super.key,
    required this.name,
    this.shared = false,
    this.size = 40,
  });

  final String name;
  final bool shared;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final well = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.sunken, shape: BoxShape.circle),
      child: Text(
        pendingInitials(name),
        style: t.labelStrong.copyWith(fontSize: size * 0.34, height: 1),
      ),
    );
    if (!shared) return ExcludeSemantics(child: well);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            well,
            PositionedDirectional(
              end: -3,
              bottom: -3,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.line),
                ),
                child: Icon(LucideIcons.link2, size: 11, color: c.inkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One pending item as a ledger row: who (or what), how long it has
/// waited, the amount and which side it is on. Swipe right to settle;
/// long-press for quick actions.
class PendingRow extends StatelessWidget {
  const PendingRow({
    super.key,
    required this.view,
    this.onTap,
    this.onSettle,
    this.onLongPress,
    this.grouped = false,
    this.inSplit = false,
  });

  final PendingView view;
  final VoidCallback? onTap;
  final VoidCallback? onSettle;
  final VoidCallback? onLongPress;

  /// Under a person: the purpose leads and the person is implied.
  final bool grouped;

  /// Under a split bill: the person leads and the bill is implied.
  final bool inSplit;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final p = view.payment;
    final dir = p.direction;
    final active = view.status.isActive;
    final shown = pendingShownAmount(view);
    final nested = grouped || inSplit;
    final long = view.isLongPending;

    final String title = grouped ? p.purpose : p.counterparty;
    final String what = grouped
        ? p.kind.label
        : (inSplit ? p.split!.partLabel : p.purpose);
    final String state = switch (view.status) {
      PendingStatus.settled =>
        view.settledOn == null
            ? 'settled'
            : 'settled ${DateFormats.dayMonth.format(view.settledOn!)}',
      PendingStatus.cancelled => 'written off',
      _ => pendingDays(view.daysOpen).toLowerCase(),
    };

    // Nested rows keep the well's slot so their text lines up under the
    // header; a shared one shows the link mark there instead.
    final Widget leading = nested
        ? SizedBox(
            width: 40,
            child: p.isShared
                ? Icon(LucideIcons.link2, size: 16, color: c.inkSoft)
                : null,
          )
        : PendingInitials(name: p.counterparty, shared: p.isShared);

    final semantics =
        '${dir.sentence(p.counterparty)} ${pendingSpoken(context, shown)} for ${p.purpose}. '
        '${view.status.label}. ${active ? '${pendingDays(view.daysOpen)} open' : state}.'
        '${p.isShared ? ' Shared on FiNN.' : ''}';

    Widget row = LedgerRow(
      leading: leading,
      title: title,
      subtitle: '$what, $state',
      subtitleColor: active && long ? c.amber : null,
      trailing: AmountText(
        shown,
        style: t.figure.copyWith(
          color: pendingAmountColor(context, dir, active: active),
        ),
      ),
      trailingSub: Text(
        active
            ? pendingSideLabel(dir)
            : (view.status == PendingStatus.settled
                  ? 'settled'
                  : 'written off'),
        style: t.small,
      ),
      below: view.status == PendingStatus.partiallySettled
          ? LedgerBar(value: view.settledBps / 10000, height: 4)
          : null,
      semanticLabel: semantics,
      onTap: onTap,
      onLongPress: onLongPress,
    );

    if (active && onSettle != null) {
      row = Dismissible(
        key: ValueKey('swipe-${p.id}'),
        direction: DismissDirection.startToEnd,
        dismissThresholds: const {DismissDirection.startToEnd: 0.32},
        confirmDismiss: (_) async {
          HapticFeedback.mediumImpact();
          onSettle!();
          return false;
        },
        background: ColoredBox(
          color: c.green,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
            child: Row(
              children: [
                Icon(LucideIcons.circleCheck, color: c.onInk, size: 20),
                const SizedBox(width: Sp.sm),
                Text('Settle', style: t.labelStrong.copyWith(color: c.onInk)),
              ],
            ),
          ),
        ),
        child: row,
      );
    }
    return Semantics(
      container: true,
      onLongPressHint: onLongPress == null ? null : 'Quick actions',
      customSemanticsActions: active && onSettle != null
          ? {
              CustomSemanticsAction(
                label: dir.isOwe ? 'Settle, I paid' : 'Settle, I received',
              ): onSettle!,
            }
          : null,
      child: row,
    );
  }
}

// ---------------------------------------------------------------------------
// View options sheet (sort + filters)
// ---------------------------------------------------------------------------

Future<PendingFilter?> showPendingViewOptions(
  BuildContext context,
  PendingFilter current,
) => showFinnSheet<PendingFilter>(
  context,
  builder: (_) => PendingViewSheet(initial: current),
);

/// Sort and filter the list in one place, with a live result count.
class PendingViewSheet extends ConsumerStatefulWidget {
  const PendingViewSheet({super.key, required this.initial});

  final PendingFilter initial;

  @override
  ConsumerState<PendingViewSheet> createState() => _PendingViewSheetState();
}

class _PendingViewSheetState extends ConsumerState<PendingViewSheet> {
  late PendingFilter _f = widget.initial;

  void _set(PendingFilter f) => setState(() => _f = f);

  Set<T> _toggle<T>(Set<T> s, T v) {
    final next = Set<T>.of(s);
    if (!next.remove(v)) next.add(v);
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(pendingViewsProvider).value ?? const <PendingView>[];
    final n = filterPending(all, _f).length;
    final canReset =
        !(_f.activeCount == 0 &&
            _f.sort == PendingSort.waiting &&
            _f.groupByPerson);
    return FinnSheetScaffold(
      title: 'Sort and filter',
      description:
          'Filters apply within the ${_f.tab.label.toLowerCase()} list.',
      footer: Row(
        children: [
          LedgerButton(
            label: 'Reset',
            variant: LedgerButtonVariant.quiet,
            onPressed: canReset
                ? () => _set(PendingFilter(tab: _f.tab, query: _f.query))
                : null,
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: LedgerButton(
              key: const ValueKey('pending-apply'),
              label: n == 0
                  ? 'No matches'
                  : 'Show $n ${n == 1 ? 'item' : 'items'}',
              expand: true,
              onPressed: () => Navigator.of(context).pop(_f),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerField(
            label: 'Sort by',
            child: LedgerChoiceChips<PendingSort>(
              options: [
                for (final s in PendingSort.values)
                  LedgerOption(s, s.label, icon: s.icon),
              ],
              selected: _f.sort,
              onChanged: (s) => _set(_f.copyWith(sort: s)),
            ),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerField(
            label: 'Money',
            child: LedgerSegmented<PendingDirection?>(
              segments: const [
                LedgerSegment(null, 'Both'),
                LedgerSegment(PendingDirection.iOwe, 'I owe'),
                LedgerSegment(PendingDirection.owedToMe, 'Owed to me'),
              ],
              selected: _f.direction,
              onChanged: (d) => _set(_f.copyWith(direction: () => d)),
            ),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerField(
            label: 'Waiting',
            child: _MultiChips<PendingAge>(
              options: [
                for (final d in PendingAge.values) (d, d.label, d.icon),
              ],
              selected: _f.ages,
              onToggle: (d) => _set(_f.copyWith(ages: _toggle(_f.ages, d))),
            ),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerField(
            label: 'Reason',
            child: _MultiChips<PendingKind>(
              options: [for (final k in PendingKind.values) (k, k.label, null)],
              selected: _f.kinds,
              onToggle: (k) => _set(_f.copyWith(kinds: _toggle(_f.kinds, k))),
            ),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerSwitchRow(
            title: 'Group by person',
            subtitle: 'Keep several items with one person together',
            value: _f.groupByPerson,
            onChanged: (b) => _set(_f.copyWith(groupByPerson: b)),
          ),
        ],
      ),
    );
  }
}

/// Several chips that can each be on or off.
class _MultiChips<T> extends StatelessWidget {
  const _MultiChips({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<(T, String, IconData?)> options;
  final Set<T> selected;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Sp.sm,
    runSpacing: Sp.sm,
    children: [
      for (final o in options)
        LedgerChip(
          label: o.$2,
          icon: o.$3,
          selected: selected.contains(o.$1),
          onTap: () => onToggle(o.$1),
        ),
    ],
  );
}
