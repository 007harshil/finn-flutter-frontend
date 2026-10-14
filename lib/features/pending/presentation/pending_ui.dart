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
  }) =>
      PendingFilter(
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
      tab, direction, query, sort, Object.hashAllUnordered(ages), Object.hashAllUnordered(kinds), groupByPerson);
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
  final splits = groups.keys.any((k) => k.startsWith('split:')) ? PendingSplitView.collect(all) : const <String, PendingSplitView>{};
  return [
    for (final MapEntry(:key, value: g) in groups.entries)
      if (key.startsWith('split:'))
        PendingSplitEntry(
          split: splits[key.substring(6)]!,
          // People in the order they were added, like the bill.
          items: [for (final m in splits[key.substring(6)]!.members) if (g.contains(m)) m],
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
  int get hashCode => Object.hash(toPay, toCollect, payCount, collectCount, longToPay, longToCollect, longCount,
      people, Object.hashAll(oldest), Object.hashAll(PendingTab.values.map((t) => counts[t])));
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
  final text = 'Hi ${p.counterparty.split(' ').first}, a gentle reminder about '
      '${MoneyFormatter.format(v.outstanding, decimals: DecimalDisplay.none)} for ${p.purpose}$since. Thanks!';
  final box = context.findRenderObject() as RenderBox?;
  return SharePlus.instance.share(ShareParams(
    text: text,
    sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  ));
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

/// Colour for how long an item has waited: quiet when recent, warmer as it
/// ages. Informative, never alarming red.
Color pendingAgeColor(PendingView v, FinnColors c) => switch (PendingAge.of(v)) {
      PendingAge.fresh => c.textTertiary,
      PendingAge.weeks => c.textSecondary,
      PendingAge.long => c.warning,
    };

/// Label, colour and icon for an item's age or closed state (never colour
/// alone).
({String label, Color color, IconData icon}) pendingAgeInfo(PendingView view, FinnColors c) {
  switch (view.status) {
    case PendingStatus.settled:
      final on = view.settledOn;
      return (
        label: on == null ? 'Settled' : 'Settled ${DateFormats.dayMonth.format(on)}',
        color: c.positive,
        icon: LucideIcons.circleCheck,
      );
    case PendingStatus.cancelled:
      return (label: 'Written off', color: c.textSecondary, icon: LucideIcons.ban);
    case PendingStatus.open || PendingStatus.partiallySettled:
      return (label: pendingDays(view.daysOpen), color: pendingAgeColor(view, c), icon: LucideIcons.hourglass);
  }
}

/// Age / status chip for a pending item (icon + text, not colour only).
class PendingAgeChip extends StatelessWidget {
  const PendingAgeChip({super.key, required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final i = pendingAgeInfo(view, context.colors);
    return StatusPill(label: i.label, color: i.color, icon: i.icon);
  }
}

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

/// Initials in a circle with a ring that fills as the item is settled, and
/// a small arrow badge for the direction money flows.
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
    final c = context.colors;
    final fg = onGradient ? Colors.white : color;
    final track = onGradient ? Colors.white.withValues(alpha: 0.22) : color.withValues(alpha: c.isDark ? 0.22 : 0.14);
    final badge = size * 0.42;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                duration: context.motion.progress,
                curve: Curves2.emphasized,
                builder: (context, p, _) => CustomPaint(
                  painter: _RingPainter(progress: p, color: fg, track: track),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(size * 0.1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onGradient ? Colors.white.withValues(alpha: 0.16) : color.withValues(alpha: c.isDark ? 0.2 : 0.12),
                  ),
                  child: Center(
                    child: Text(
                      pendingInitials(name),
                      style: context.text.label.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        fontSize: size * 0.3,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (direction != null)
              PositionedDirectional(
                end: -2,
                bottom: -2,
                child: Container(
                  width: badge,
                  height: badge,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onGradient ? Colors.white : direction!.color(c),
                    border: Border.all(color: onGradient ? Colors.transparent : c.surface, width: 2),
                  ),
                  child: Icon(direction!.icon, size: badge * 0.6, color: onGradient ? direction!.color(c) : Colors.white),
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
    final stroke = size.width * 0.07;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
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
/// when. Swipe right to settle; long-press for quick actions.
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
    final c = context.colors;
    final t = context.text;
    final p = view.payment;
    final dir = p.direction;
    final active = view.status.isActive;
    final tone = active ? dir.color(c) : c.textSecondary;
    final age = pendingAgeInfo(view, c);
    final shown = pendingShownAmount(view);
    final partial = view.status == PendingStatus.partiallySettled;
    final semantics = '${dir.sentence(p.counterparty)} ${MoneyFormatter.spoken(shown)} for ${p.purpose}. '
        '${view.status.label}. ${active ? '${pendingDays(view.daysOpen)} open' : age.label}';
    final shared = p.isShared ? ' Shared on FiNN.' : '';

    final leading = grouped
        ? IconTile(
            icon: active ? dir.icon : (view.status == PendingStatus.settled ? LucideIcons.check : LucideIcons.ban),
            background: active ? dir.soft(c) : c.surfaceMuted,
            foreground: tone,
            size: 30,
            radius: Radii.md,
            iconSize: 15,
          )
        : PendingAvatar(
            size: inSplit ? 32 : 40,
            name: p.counterparty,
            color: tone,
            progress: view.settledBps / 10000,
            direction: active ? dir : null,
          );

    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: Space.x3, vertical: grouped || inSplit ? Space.x2_5 : Space.x3),
      child: Row(
        children: [
          leading,
          const SizedBox(width: Space.x3),
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
                              style: grouped ? t.body.copyWith(fontWeight: FontWeight.w700) : t.bodyStrong,
                            ),
                          ),
                          if (p.isSplit && !grouped && !inSplit) ...[
                            const SizedBox(width: Space.x1),
                            Icon(LucideIcons.users, size: 13, color: c.textTertiary),
                          ],
                          if (p.isShared && !grouped) ...[
                            const SizedBox(width: Space.x1),
                            Icon(LucideIcons.link2, size: 13, color: c.info),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.x2),
                    AmountText(shown, style: t.amountSmall.copyWith(color: tone)),
                  ],
                ),
                const SizedBox(height: 3),
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
                    const SizedBox(width: Space.x2),
                    Icon(age.icon, size: 12, color: age.color),
                    const SizedBox(width: 3),
                    Text(age.label, style: t.micro.copyWith(color: age.color, fontWeight: FontWeight.w800)),
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
    final c = context.colors;
    return ColoredBox(
      color: c.positive,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x5),
        child: Row(
          children: [
            Icon(LucideIcons.circleCheckBig, color: c.onSolid, size: 20),
            const SizedBox(width: Space.x2),
            Text(
              direction.isOwe ? 'Settle · I paid' : 'Settle · I received',
              style: context.text.label.copyWith(color: c.onSolid, fontWeight: FontWeight.w800),
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
    showFinnSheet<PendingFilter>(context, builder: (_) => PendingViewSheet(initial: current));

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
    final t = context.text;
    final all = ref.watch(pendingViewsProvider).value ?? const <PendingView>[];
    final n = filterPending(all, _f).length;
    return FinnSheetScaffold(
      title: 'Sort & filter',
      footer: Row(
        children: [
          FinnButton(
            label: 'Reset',
            variant: FinnButtonVariant.ghost,
            onPressed: _f.activeCount == 0 && _f.sort == PendingSort.waiting && _f.groupByPerson
                ? null
                : () => _set(PendingFilter(tab: _f.tab, query: _f.query)),
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            child: FinnButton(
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
          const PendingFieldLabel('Sort by'),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final s in PendingSort.values)
                _OptionChip(
                  label: s.label,
                  icon: s.icon,
                  selected: _f.sort == s,
                  onTap: () => _set(_f.copyWith(sort: s)),
                ),
            ],
          ),
          const SizedBox(height: Space.x5),
          const PendingFieldLabel('Money'),
          SegmentedTabs<PendingDirection?>(
            items: const [
              SegmentItem(null, 'Both'),
              SegmentItem(PendingDirection.iOwe, 'I owe'),
              SegmentItem(PendingDirection.owedToMe, 'Owed to me'),
            ],
            selected: _f.direction,
            onChanged: (d) => _set(_f.copyWith(direction: () => d)),
          ),
          const SizedBox(height: Space.x5),
          const PendingFieldLabel('Waiting'),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final d in PendingAge.values)
                _OptionChip(
                  label: d.label,
                  icon: d.icon,
                  selected: _f.ages.contains(d),
                  onTap: () => _set(_f.copyWith(ages: _toggle(_f.ages, d))),
                ),
            ],
          ),
          const SizedBox(height: Space.x5),
          const PendingFieldLabel('Reason'),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final k in PendingKind.values)
                _OptionChip(
                  label: k.label,
                  selected: _f.kinds.contains(k),
                  onTap: () => _set(_f.copyWith(kinds: _toggle(_f.kinds, k))),
                ),
            ],
          ),
          const SizedBox(height: Space.x4),
          _SwitchRow(
            title: 'Group by person',
            subtitle: 'Keep several items with one person together',
            value: _f.groupByPerson,
            onChanged: (b) => _set(_f.copyWith(groupByPerson: b)),
          ),
          Text('Filters apply within the ${_f.tab.label.toLowerCase()} list.', style: t.micro),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.x2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.bodyStrong),
                  Text(subtitle, style: t.caption),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Selectable pill used in the options sheet and the quick filter bar.
class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onPrimary : c.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: Radii.rFull,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: context.motion.fast,
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            decoration: BoxDecoration(
              color: selected ? c.primary : c.surface,
              borderRadius: Radii.rFull,
              border: Border.all(color: selected ? c.primary : c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected || icon != null) ...[
                  Icon(selected ? LucideIcons.check : icon, size: 14, color: fg),
                  const SizedBox(width: Space.x1_5),
                ],
                Text(label, style: context.text.label.copyWith(color: fg, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
