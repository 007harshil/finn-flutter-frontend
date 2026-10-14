import 'dart:math' as math;

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
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/pending_payment.dart';

/// Presentation helpers for [PendingDirection]: never colour alone — every
/// direction also has an icon and a plain-language label.
extension PendingDirectionUi on PendingDirection {
  bool get isOwe => this == PendingDirection.iOwe;

  IconData get icon => isOwe ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft;

  Color color(FinnColors c) => isOwe ? c.negative : c.positive;

  Color soft(FinnColors c) => isOwe ? c.negativeSoft : c.positiveSoft;

  /// Luxe tone: what you pay reads warm-red, what comes back reads green.
  Color tone(LuxePalette p) => isOwe ? p.negative : p.positive;

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
  int get activeCount => (direction != null ? 1 : 0) + ages.length + kinds.length;

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
  PendingFilter cleared() => PendingFilter(tab: tab, query: query, sort: sort, groupByPerson: groupByPerson);

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
  const PendingPersonGroup({required this.name, required this.items, required this.toPay, required this.toCollect});
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
  (ref) => PendingSplitView.collect(ref.watch(pendingViewsProvider).value ?? const []),
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
    if (v.payment.split case final s?) splitCounts[s.id] = (splitCounts[s.id] ?? 0) + 1;
  }
  final groups = <String, List<PendingView>>{};
  for (final v in items) {
    final s = v.payment.split;
    final key = s != null && splitCounts[s.id]! > 1
        ? 'split:${s.id}'
        : (f.groupByPerson ? 'person:${v.payment.counterparty.trim().toLowerCase()}' : 'item:${v.payment.id}');
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
          toPay: Money.sum(g.where((v) => v.payment.direction.isOwe).map((v) => v.outstanding)),
          toCollect: Money.sum(g.where((v) => !v.payment.direction.isOwe).map((v) => v.outstanding)),
        ),
  ];
}

/// Amount a row shows: what is left while active, else the original.
Money pendingShownAmount(PendingView v) => v.status.isActive ? v.outstanding : v.payment.originalAmount;

int _compare(PendingView a, PendingView b, PendingFilter f) {
  final pa = a.payment, pb = b.payment;
  final int r = switch (f.sort) {
    PendingSort.waiting => switch (f.tab) {
      PendingTab.active => () {
        final age = pa.createdDate.compareTo(pb.createdDate);
        return age != 0 ? age : pendingShownAmount(b).compareTo(pendingShownAmount(a));
      }(),
      PendingTab.settled => (b.settledOn ?? pb.updatedAt).compareTo(a.settledOn ?? pa.updatedAt),
      PendingTab.writtenOff => pb.updatedAt.compareTo(pa.updatedAt),
    },
    PendingSort.amount => pendingShownAmount(b).compareTo(pendingShownAmount(a)),
    PendingSort.newest => pb.createdDate.compareTo(pa.createdDate),
    PendingSort.name => pa.counterparty.toLowerCase().compareTo(pb.counterparty.toLowerCase()),
  };
  return r != 0 ? r : pa.purpose.toLowerCase().compareTo(pb.purpose.toLowerCase());
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
      longToPay: Money.sum(long.where((v) => v.payment.direction.isOwe).map((v) => v.outstanding)),
      longToCollect: Money.sum(long.where((v) => !v.payment.direction.isOwe).map((v) => v.outstanding)),
      longCount: long.length,
      people: active.map((v) => v.payment.counterparty.trim().toLowerCase()).toSet().length,
      oldest: (List.of(active)..sort((a, b) => b.daysOpen.compareTo(a.daysOpen))).take(3).toList(),
      counts: {for (final t in PendingTab.values) t: all.where((v) => t.matches(v.status)).length},
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
String pendingDays(int days) => days <= 0 ? 'Today' : '$days ${days == 1 ? 'day' : 'days'}';

/// Plain, informative status: "Ramesh has not returned your money · 40 days
/// have passed" / "You have not paid Rahul back · 24 days have passed".
String pendingAgeSentence(PendingView v) {
  final who = v.payment.counterparty;
  final d = v.daysOpen;
  final passed = d <= 0 ? 'Started today' : '$d ${d == 1 ? 'day has' : 'days have'} passed';
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
    ShareParams(text: text, sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size),
  );
}

/// "PN" for "Priya Nair", "S" for "Society".
String pendingInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  if (parts.length == 1) return first.toUpperCase();
  return (first + parts.last.characters.first).toUpperCase();
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// Tone for how long an item has waited: quiet when recent, warmer as it
/// ages. Informative, never alarming red.
Color pendingAgeColor(PendingView v, LuxePalette p) => switch (PendingAge.of(v)) {
  PendingAge.fresh => p.inkMute,
  PendingAge.weeks => p.inkSoft,
  PendingAge.long => p.warning,
};

/// Label, colour and icon for an item's age or closed state (never colour
/// alone).
({String label, Color color, IconData icon}) pendingAgeInfo(PendingView view, LuxePalette p) {
  switch (view.status) {
    case PendingStatus.settled:
      final on = view.settledOn;
      return (
        label: on == null ? 'Settled' : 'Settled ${DateFormats.dayMonth.format(on)}',
        color: p.positive,
        icon: LucideIcons.circleCheck,
      );
    case PendingStatus.cancelled:
      return (label: 'Written off', color: p.inkMute, icon: LucideIcons.ban);
    case PendingStatus.open || PendingStatus.partiallySettled:
      return (label: pendingDays(view.daysOpen), color: pendingAgeColor(view, p), icon: LucideIcons.hourglass);
  }
}

/// Age / status chip for a pending item (icon + text, not colour only).
class PendingAgeChip extends StatelessWidget {
  const PendingAgeChip({super.key, required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final i = pendingAgeInfo(view, context.luxe);
    return LuxeStatus(label: i.label, color: i.color, icon: i.icon);
  }
}

class PendingDirectionLabel extends StatelessWidget {
  const PendingDirectionLabel({super.key, required this.direction, this.onGradient = false});

  final PendingDirection direction;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final color = onGradient ? p.gold : direction.tone(p);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(direction.icon, size: 13, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            direction.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.lt.eyebrow.c(color),
          ),
        ),
      ],
    );
  }
}

/// Initials in a circle with a fine ring that fills as the item is
/// settled, and a small arrow badge for the direction money flows.
class PendingAvatar extends StatelessWidget {
  const PendingAvatar({
    super.key,
    required this.name,
    required this.color,
    this.progress = 0,
    this.direction,
    this.size = 40,
    this.onGradient = false,
  });

  final String name;
  final Color color;

  /// Settled share, 0..1. The ring grows to it once.
  final double progress;
  final PendingDirection? direction;
  final double size;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final fg = onGradient ? p.onObsidian : color;
    final track = onGradient ? p.onObsidian.withValues(alpha: 0.14) : p.line;
    final badge = size * 0.4;
    final d = direction;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DrawIn(
                value: progress.clamp(0.0, 1.0),
                builder: (context, v) => CustomPaint(
                  painter: _RingPainter(progress: v, color: onGradient ? p.gold : p.positive, track: track),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(size * 0.1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onGradient ? p.onObsidian.withValues(alpha: 0.08) : p.tint(color, 0.09),
                  ),
                  child: Center(
                    child: Text(
                      pendingInitials(name),
                      style: context.lt.label
                          .w(750)
                          .copyWith(color: fg, fontSize: size * 0.3, height: 1, letterSpacing: 0.4),
                    ),
                  ),
                ),
              ),
            ),
            if (d != null)
              PositionedDirectional(
                end: -2,
                bottom: -2,
                child: Container(
                  width: badge,
                  height: badge,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onGradient ? p.gold : d.tone(p),
                    border: Border.all(color: onGradient ? p.obsidian : p.paper, width: 2),
                  ),
                  child: Icon(d.icon, size: badge * 0.58, color: onGradient ? p.obsidian : p.paper),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color, required this.track});

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(1.5, size.width * 0.045);
    final arc = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, math.pi * 2, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * progress, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}

/// One pending item as a compact two-line row: who, what, how much and
/// how long. Swipe right to settle; long-press for quick actions.
class PendingRow extends StatelessWidget {
  const PendingRow({
    super.key,
    required this.view,
    required this.onTap,
    this.onSettle,
    this.onLongPress,
    this.grouped = false,
    this.inSplit = false,
  });

  final PendingView view;
  final VoidCallback onTap;
  final VoidCallback? onSettle;
  final VoidCallback? onLongPress;

  /// Inside a person card: the purpose leads and the person is implied.
  final bool grouped;

  /// Inside a split card: the person leads and the bill is implied.
  final bool inSplit;

  @override
  Widget build(BuildContext context) {
    final lp = context.luxe;
    final t = context.lt;
    final p = view.payment;
    final dir = p.direction;
    final active = view.status.isActive;
    final tone = active ? dir.tone(lp) : lp.inkMute;
    final age = pendingAgeInfo(view, lp);
    final shown = pendingShownAmount(view);
    final partial = view.status == PendingStatus.partiallySettled;
    final semantics =
        '${dir.sentence(p.counterparty)} ${MoneyFormatter.spoken(shown)} for ${p.purpose}. '
        '${view.status.label}. ${active ? '${pendingDays(view.daysOpen)} open' : age.label}';
    final shared = p.isShared ? ' Shared on FiNN.' : '';

    final leading = grouped
        ? Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(shape: BoxShape.circle, color: lp.tint(tone, 0.09)),
            child: Icon(
              active ? dir.icon : (view.status == PendingStatus.settled ? LucideIcons.check : LucideIcons.ban),
              size: 15,
              color: tone,
            ),
          )
        : PendingAvatar(
            size: inSplit ? 34 : 42,
            name: p.counterparty,
            color: tone,
            progress: view.settledBps / 10000,
            direction: active ? dir : null,
          );

    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: grouped || inSplit ? 12 : 15),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              grouped ? p.purpose : p.counterparty,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: grouped ? t.label.w(700).c(lp.ink) : t.heading.copyWith(fontSize: 15),
                            ),
                          ),
                          if (p.isSplit && !grouped && !inSplit) ...[
                            const SizedBox(width: 6),
                            Icon(LucideIcons.users, size: 13, color: lp.inkMute),
                          ],
                          if (p.isShared && !grouped) ...[
                            const SizedBox(width: 6),
                            Icon(LucideIcons.link2, size: 13, color: lp.info),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    LuxeAmount(shown, fit: false, style: t.number.copyWith(color: tone)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        partial
                            ? '${grouped || inSplit ? '' : '${p.purpose} · '}${view.settledBps ~/ 100}% settled'
                            : (grouped ? p.kind.label : (inSplit ? p.split!.partLabel : p.purpose)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.caption,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(age.icon, size: 11, color: age.color),
                    const SizedBox(width: 4),
                    Text(age.label, style: t.micro.w(700).c(age.color)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget child = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        splashColor: lp.gold.withValues(alpha: 0.08),
        highlightColor: lp.sunk.withValues(alpha: 0.6),
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress!();
              },
        child: row,
      ),
    );

    if (active && onSettle != null) {
      child = Dismissible(
        key: ValueKey('swipe-${p.id}'),
        direction: DismissDirection.startToEnd,
        dismissThresholds: const {DismissDirection.startToEnd: 0.32},
        confirmDismiss: (_) async {
          HapticFeedback.mediumImpact();
          onSettle!();
          return false;
        },
        background: _SwipeSettleBackground(direction: dir),
        child: child,
      );
    }
    return Semantics(
      button: true,
      label: '$semantics$shared',
      excludeSemantics: true,
      onLongPressHint: onLongPress == null ? null : 'Quick actions',
      customSemanticsActions: active && onSettle != null
          ? {CustomSemanticsAction(label: dir.isOwe ? 'Settle, I paid' : 'Settle, I received'): onSettle!}
          : null,
      child: child,
    );
  }
}

class _SwipeSettleBackground extends StatelessWidget {
  const _SwipeSettleBackground({required this.direction});

  final PendingDirection direction;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: p.goldGradient),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            const Icon(LucideIcons.circleCheckBig, color: Color(0xFF17130C), size: 20),
            const SizedBox(width: 10),
            Text(
              direction.isOwe ? 'Settle · I paid' : 'Settle · I received',
              style: context.lt.label.w(750).c(const Color(0xFF17130C)),
            ),
          ],
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

// ---------------------------------------------------------------------------
// View options sheet (sort + filters)
// ---------------------------------------------------------------------------

Future<PendingFilter?> showPendingViewOptions(BuildContext context, PendingFilter current) =>
    showLuxeSheet<PendingFilter>(context, builder: (_) => PendingViewSheet(initial: current));

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
    final p = context.luxe;
    final t = context.lt;
    final all = ref.watch(pendingViewsProvider).value ?? const <PendingView>[];
    final n = filterPending(all, _f).length;
    final pristine = _f.activeCount == 0 && _f.sort == PendingSort.waiting && _f.groupByPerson;
    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(s.toUpperCase(), style: t.eyebrow),
    );
    return LuxeSheet(
      eyebrow: 'Money owed',
      title: 'Sort & filter',
      footer: Row(
        children: [
          LuxeButton(
            label: 'Reset',
            variant: LuxeButtonVariant.ghost,
            onPressed: pristine ? null : () => _set(PendingFilter(tab: _f.tab, query: _f.query)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LuxeButton(
              key: const ValueKey('pending-apply'),
              label: n == 0 ? 'No matches' : 'Show $n ${n == 1 ? 'item' : 'items'}',
              expand: true,
              onPressed: () => Navigator.of(context).pop(_f),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label('Sort by'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in PendingSort.values)
                LuxeChip(
                  label: s.label,
                  icon: _f.sort == s ? LucideIcons.check : s.icon,
                  selected: _f.sort == s,
                  onTap: () => _set(_f.copyWith(sort: s)),
                ),
            ],
          ),
          const SizedBox(height: 22),
          label('Money'),
          LuxeSegmented<PendingDirection?>(
            segments: const [
              LuxeSegment(null, 'Both'),
              LuxeSegment(PendingDirection.iOwe, 'I owe'),
              LuxeSegment(PendingDirection.owedToMe, 'Owed to me'),
            ],
            selected: _f.direction,
            onChanged: (d) => _set(_f.copyWith(direction: () => d)),
          ),
          const SizedBox(height: 22),
          label('Waiting'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final d in PendingAge.values)
                LuxeChip(
                  label: d.label,
                  icon: _f.ages.contains(d) ? LucideIcons.check : d.icon,
                  selected: _f.ages.contains(d),
                  onTap: () => _set(_f.copyWith(ages: _toggle(_f.ages, d))),
                ),
            ],
          ),
          const SizedBox(height: 22),
          label('Reason'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final k in PendingKind.values)
                LuxeChip(
                  label: k.label,
                  icon: _f.kinds.contains(k) ? LucideIcons.check : null,
                  selected: _f.kinds.contains(k),
                  onTap: () => _set(_f.copyWith(kinds: _toggle(_f.kinds, k))),
                ),
            ],
          ),
          const SizedBox(height: 18),
          MergeSemantics(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: p.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Group by person', style: t.label.w(700).c(p.ink)),
                        Text('Keep several items with one person together', style: t.caption),
                      ],
                    ),
                  ),
                  Switch(
                    value: _f.groupByPerson,
                    activeTrackColor: p.ink,
                    onChanged: (b) => _set(_f.copyWith(groupByPerson: b)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text('Filters apply within the ${_f.tab.label.toLowerCase()} list.', style: t.micro),
        ],
      ),
    );
  }
}
