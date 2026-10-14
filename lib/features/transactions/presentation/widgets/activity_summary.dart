import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/time/dates.dart';
import '../../../../design_system/design_system.dart';
import '../../../../design_system/luxe/luxe.dart';
import '../../../categories/domain/category.dart';
import '../../application/transaction_filter.dart';
import '../../domain/transaction.dart';

/// Ids of the non-category parts of the money bar.
const String _otherId = '_other';
const String _keptId = '_kept';

/// Most categories named in the bar; the rest fold into "Other".
const int _barCategories = 4;

/// The filtered period in one glance.
///
/// A verdict ("Kept 44% of income") over one serif figure; a bar of where
/// the money went (income is the full width, each spending category takes
/// its share, the rest is kept) whose slices and legend filter the list;
/// "Daily" unfolds a scrubbable day-by-day chart with three quick facts.
class ActivitySummary extends ConsumerStatefulWidget {
  const ActivitySummary({super.key, required this.feed});

  final TransactionFeed feed;

  @override
  ConsumerState<ActivitySummary> createState() => _ActivitySummaryState();
}

class _ActivitySummaryState extends ConsumerState<ActivitySummary> {
  static const _storageKey = 'activity-summary-expanded';
  bool _expanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _expanded = PageStorage.maybeOf(context)?.readState(context, identifier: _storageKey) as bool? ?? _expanded;
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    PageStorage.maybeOf(context)?.writeState(context, _expanded, identifier: _storageKey);
  }

  void _toggleCategory(String id) {
    HapticFeedback.selectionClick();
    ref.read(transactionFilterProvider.notifier).toggleCategory(id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final feed = widget.feed;
    final f = feed.filter;
    final cats = ref.watch(categoriesByIdProvider).value ?? const <String, TransactionCategory>{};
    final today = ref.watch(todayProvider);
    final incomeMode = f.type == TransactionType.income;
    final story = _Story.of(feed, incomeMode);
    final bar = _BarModel.of(feed, cats, incomeMode, p);

    return LuxeCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${feed.count} transaction${feed.count == 1 ? '' : 's'} · ${_periodShort(f)}'.toUpperCase(),
                  style: t.eyebrow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _Delta(feed: feed, incomeMode: incomeMode, today: today),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        story.caption,
                        style: t.caption.w(650).c(p.inkSoft),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      LuxeAmount(
                        story.amount,
                        style: t.display.copyWith(fontSize: 40, color: story.color(p)),
                        countFromZero: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Flow(icon: LucideIcons.arrowDownLeft, label: 'In', amount: feed.income, color: p.positive),
                  const SizedBox(height: 4),
                  _Flow(icon: LucideIcons.arrowUpRight, label: 'Out', amount: -feed.expense, color: p.ink),
                ],
              ),
            ],
          ),
          if (bar.total > 0) ...[
            const SizedBox(height: 18),
            _MoneyBar(model: bar, selected: f.categoryIds, cats: cats, onTap: _toggleCategory),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in bar.legend) ...[
                        LuxeChip(
                          key: ValueKey('pulse-legend:${s.id}'),
                          label: '${cats[s.id]?.name ?? 'Other'}  ${bar.percentOf(s)}%',
                          dot: s.color,
                          height: 32,
                          selected: f.categoryIds.contains(s.id),
                          semanticLabel:
                              '${cats[s.id]?.name ?? 'Other'}, ${bar.percentOf(s)} percent. '
                              '${f.categoryIds.contains(s.id) ? 'Remove filter' : 'Show only these'}',
                          onTap: s.isCategory ? () => _toggleCategory(s.id) : null,
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _DailyToggle(expanded: _expanded, onTap: _toggle),
            ],
          ),
          MotionAnimatedSize(
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _Daily(feed: feed, today: today, cats: cats),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

String _periodShort(TransactionFilter f) {
  if (!f.hasCustomRange) return DateFormats.shortMonthYear.format(f.month.start);
  final r = f.range;
  final start = r.start.year == r.end.year
      ? DateFormats.dayMonth.format(r.start)
      : DateFormats.dayMonthYear.format(r.start);
  return '$start – ${DateFormats.dayMonthYear.format(r.end)}';
}

String _money(BuildContext context, Money m, {bool compact = false}) {
  if (AmountVisibility.hiddenOf(context)) return MoneyFormatter.masked;
  return compact ? MoneyFormatter.compact(m) : MoneyFormatter.format(m, decimals: DecimalDisplay.none);
}

enum _Outcome { kept, overspent, spent, earned, quiet }

/// The one-line verdict for the period.
@immutable
class _Story {
  const _Story(this.outcome, this.amount, this.caption);

  final _Outcome outcome;
  final Money amount;
  final String caption;

  Color color(LuxePalette p) => switch (outcome) {
    _Outcome.kept || _Outcome.earned => p.positive,
    _Outcome.overspent => p.negative,
    _Outcome.spent || _Outcome.quiet => p.ink,
  };

  static _Story of(TransactionFeed feed, bool incomeMode) {
    final inc = feed.income;
    final exp = feed.expense;
    if (incomeMode || (exp.isZero && inc.isPositive)) {
      final n = feed.incomeByCategory.length;
      return _Story(_Outcome.earned, inc, n <= 1 ? 'Earned' : 'Earned from $n sources');
    }
    if (inc.isZero && exp.isZero) return const _Story(_Outcome.quiet, Money.zero, 'No money moved');
    if (inc.isZero) {
      final n = feed.expenseByCategory.length;
      return _Story(_Outcome.spent, exp, n <= 1 ? 'Spent' : 'Spent across $n categories');
    }
    final pct = (exp.paise * 100 / inc.paise).round();
    if (exp > inc) return _Story(_Outcome.overspent, exp - inc, 'Overspent · used $pct% of income');
    return _Story(_Outcome.kept, inc - exp, 'Kept ${100 - pct}% of income');
  }
}

class _Flow extends StatelessWidget {
  const _Flow({required this.icon, required this.label, required this.amount, required this.color});

  final IconData icon;
  final String label;
  final Money amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: t.micro),
          const SizedBox(width: 6),
          AmountText(
            amount,
            sign: amount.isZero ? SignDisplay.auto : SignDisplay.always,
            decimals: DecimalDisplay.none,
            style: t.numberSmall.c(amount.isZero ? context.luxe.inkSoft : color),
          ),
        ],
      ),
    );
  }
}

/// "↓ 12% vs Sep" against the comparison period.
class _Delta extends StatelessWidget {
  const _Delta({required this.feed, required this.incomeMode, required this.today});

  final TransactionFeed feed;
  final bool incomeMode;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final now = incomeMode ? feed.income : feed.expense;
    final before = incomeMode ? feed.previousIncome : feed.previousExpense;
    if (before.isZero || now.isZero) return const SizedBox.shrink();
    final pct = ((now.paise - before.paise) * 100 / before.paise).round();
    final f = feed.filter;
    final vs = f.hasCustomRange ? 'prev. period' : DateFormats.shortMonth.format(f.month.previous.start);
    final up = pct > 0;
    final good = incomeMode ? up : !up;
    final color = pct == 0 ? p.inkSoft : (good ? p.positive : p.negative);
    final what = incomeMode ? 'Income' : 'Spending';
    final spoken = pct == 0
        ? '$what same as $vs'
        : '$what ${pct.abs()} percent ${up ? 'higher' : 'lower'} than $vs'
              '${!f.hasCustomRange && f.month.contains(today) ? ' at this point' : ''}';
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: LuxeStatus(
        label: pct == 0 ? 'Same as $vs' : '${pct.abs()}% vs $vs',
        color: color,
        icon: pct == 0 ? LucideIcons.equal : (up ? LucideIcons.trendingUp : LucideIcons.trendingDown),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Money bar
// ---------------------------------------------------------------------------

@immutable
class _Seg {
  const _Seg(this.id, this.value, this.color);
  final String id;
  final double value;
  final Color color;

  bool get isCategory => id != _otherId && id != _keptId;
}

@immutable
class _BarModel {
  const _BarModel(this.segments, this.total, this.marker, this.base);

  final List<_Seg> segments;
  final double total;

  /// Where income ends (0–1) when spending exceeds it.
  final double? marker;

  /// What percentages are quoted against (income when there is income).
  final double base;

  List<_Seg> get legend => segments.where((s) => s.id != _keptId).take(3).toList();

  int percentOf(_Seg s) => base <= 0 ? 0 : (s.value * 100 / base).round();

  static _BarModel of(TransactionFeed feed, Map<String, TransactionCategory> cats, bool incomeMode, LuxePalette p) {
    final shares = incomeMode ? feed.incomeByCategory : feed.expenseByCategory;
    final segs = <_Seg>[];
    var rest = 0.0;
    for (var i = 0; i < shares.length; i++) {
      final s = shares[i];
      if (i < _barCategories) {
        segs.add(
          _Seg(
            s.categoryId,
            s.amount.paise.toDouble(),
            p.mute(AccentSwatches.solid(cats[s.categoryId]?.colorIndex ?? 6)),
          ),
        );
      } else {
        rest += s.amount.paise;
      }
    }
    if (rest > 0) segs.add(_Seg(_otherId, rest, p.inkMute));
    final inc = feed.income.paise.toDouble();
    final exp = feed.expense.paise.toDouble();
    if (incomeMode) return _BarModel(segs, inc, null, inc);
    if (inc <= 0) return _BarModel(segs, exp, null, exp);
    if (inc > exp) segs.add(_Seg(_keptId, inc - exp, p.positive));
    return _BarModel(segs, math.max(inc, exp), exp > inc ? inc / exp : null, inc);
  }
}

/// Capsule of slices with hairline gaps; widths glide when filters change.
class _MoneyBar extends StatelessWidget {
  const _MoneyBar({required this.model, required this.selected, required this.cats, required this.onTap});

  final _BarModel model;
  final Set<String> selected;
  final Map<String, TransactionCategory> cats;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final reduced = context.reduceMotion;
    final parts = [
      for (final s in model.segments)
        '${s.id == _keptId ? 'Kept' : (cats[s.id]?.name ?? 'Other')} ${model.percentOf(s)} percent',
    ];
    return Semantics(
      label: 'Where the money went: ${parts.join(', ')}',
      child: SizedBox(
        height: 18,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            var x = 0.0;
            final children = <Widget>[];
            for (final s in model.segments) {
              final width = model.total <= 0 ? 0.0 : s.value / model.total * w;
              final on = selected.isEmpty || selected.contains(s.id) || !s.isCategory;
              children.add(
                AnimatedPositioned(
                  key: ValueKey(s.id),
                  duration: reduced ? Duration.zero : LuxeDurations.base,
                  curve: LuxeCurves.arrive,
                  left: x,
                  width: math.max(0, width - 2),
                  top: 3,
                  bottom: 3,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: s.isCategory ? () => onTap(s.id) : null,
                    child: AnimatedOpacity(
                      opacity: on ? 1 : 0.28,
                      duration: LuxeDurations.quick,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: s.id == _keptId ? null : s.color,
                          gradient: s.id == _keptId
                              ? LinearGradient(
                                  colors: [s.color.withValues(alpha: 0.35), s.color.withValues(alpha: 0.7)],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              x += width;
            }
            final m = model.marker;
            if (m != null) {
              children.add(
                Positioned(
                  left: (m * w).clamp(1.0, w - 2),
                  width: 2,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: p.negative, borderRadius: BorderRadius.circular(1)),
                  ),
                ),
              );
            }
            return DrawIn(
              value: 1,
              duration: const Duration(milliseconds: 1100),
              builder: (context, v) => ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: v.clamp(0.0, 1.0),
                  child: SizedBox(
                    width: w,
                    child: Stack(children: children),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DailyToggle extends StatelessWidget {
  const _DailyToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return Semantics(
      button: true,
      expanded: expanded,
      label: expanded ? 'Hide daily details' : 'Show daily details',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        key: const ValueKey('pulse-details'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(expanded ? 'Less' : 'Daily', style: context.lt.label.w(650)),
              const SizedBox(width: 2),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
                curve: LuxeCurves.arrive,
                child: Icon(LucideIcons.chevronDown, size: 15, color: p.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily chart + quick facts
// ---------------------------------------------------------------------------

class _Daily extends StatefulWidget {
  const _Daily({required this.feed, required this.today, required this.cats});

  final TransactionFeed feed;
  final DateTime today;
  final Map<String, TransactionCategory> cats;

  @override
  State<_Daily> createState() => _DailyState();
}

class _DailyState extends State<_Daily> {
  int? _scrub;

  DateRange get _range => widget.feed.filter.range;

  /// Days per bar: one per day up to two months, then grouped.
  int get _bucket {
    final days = _range.dayCount;
    return days <= 62 ? 1 : (days / 40).ceil();
  }

  int get _elapsedDays {
    final r = _range;
    if (widget.today.isBefore(r.start)) return 0;
    if (!r.contains(widget.today)) return r.dayCount;
    return daysBetween(r.start, widget.today) + 1;
  }

  List<double> _buckets() {
    final daily = widget.feed.dailyExpense;
    final b = _bucket;
    final out = List<double>.filled((daily.length / b).ceil(), 0);
    for (var i = 0; i < daily.length; i++) {
      out[i ~/ b] += daily[i];
    }
    return out;
  }

  String _bucketLabel(int i) {
    final start = _range.start.add(Duration(days: i * _bucket));
    if (_bucket == 1) return DateFormats.shortWeekdayDayMonth.format(start);
    var end = start.add(Duration(days: _bucket - 1));
    if (end.isAfter(_range.end)) end = _range.end;
    return '${DateFormats.dayMonth.format(start)} – ${DateFormats.dayMonth.format(end)}';
  }

  void _scrubAt(double dx, double width, int n) {
    if (n == 0 || width <= 0) return;
    final i = (dx / width * n).floor().clamp(0, n - 1);
    if (i != _scrub) {
      HapticFeedback.selectionClick();
      setState(() => _scrub = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final feed = widget.feed;
    final values = _buckets();
    final elapsed = _elapsedDays;
    final elapsedBuckets = (elapsed / _bucket).ceil();
    final perDay = elapsed == 0 ? Money.zero : Money.fromPaise((feed.expense.paise / elapsed).round());
    final avgBucket = perDay.paise * _bucket.toDouble();
    final noSpend = [
      for (var i = 0; i < math.min(elapsed, feed.dailyExpense.length); i++)
        if (feed.dailyExpense[i] == 0) i,
    ].length;
    final scrub = _scrub;
    final largest = feed.largestExpense;
    final largestName = largest == null ? null : (largest.displayTitle ?? widget.cats[largest.categoryId]?.name);

    final heading = scrub == null
        ? (feed.expense.isZero ? 'No spending yet' : 'Avg ${_money(context, perDay)} a day')
        : _bucketLabel(scrub);
    final headingValue = scrub == null
        ? (_bucket == 1 ? 'Tap or drag a day' : 'Tap or drag a bar')
        : '${_money(context, Money.fromPaise(values[scrub].round()))} spent';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeHairline(vertical: 6),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.label.w(700)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                headingValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.micro.c(scrub == null ? p.inkMute : p.ink).w(scrub == null ? 600 : 750),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          label: 'Daily spending chart, average ${MoneyFormatter.spoken(perDay)} a day',
          excludeSemantics: true,
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _scrubAt(d.localPosition.dx, box.maxWidth, values.length),
              onHorizontalDragStart: (d) => _scrubAt(d.localPosition.dx, box.maxWidth, values.length),
              onHorizontalDragUpdate: (d) => _scrubAt(d.localPosition.dx, box.maxWidth, values.length),
              child: RepaintBoundary(
                child: DrawIn(
                  value: 1,
                  builder: (context, g) => CustomPaint(
                    size: Size(box.maxWidth, 72),
                    painter: _DailyPainter(
                      values: values,
                      elapsed: elapsedBuckets,
                      average: avgBucket,
                      selected: scrub,
                      grow: g,
                      bar: p.ink,
                      soft: p.lineStrong,
                      future: p.sunk,
                      guide: p.gold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Fact(label: 'Per day', value: _money(context, perDay, compact: true)),
            ),
            Expanded(
              child: _Fact(
                label: largestName == null ? 'Biggest' : 'Biggest · $largestName',
                value: largest == null ? '—' : _money(context, largest.amount, compact: true),
              ),
            ),
            Expanded(
              child: _Fact(label: 'No-spend days', value: '$noSpend'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DailyPainter extends CustomPainter {
  _DailyPainter({
    required this.values,
    required this.elapsed,
    required this.average,
    required this.selected,
    required this.grow,
    required this.bar,
    required this.soft,
    required this.future,
    required this.guide,
  });

  final List<double> values;
  final int elapsed;
  final double average;
  final int? selected;
  final double grow;
  final Color bar;
  final Color soft;
  final Color future;
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final top = math.max(values.fold<double>(0, math.max), average);
    final gap = n > 40 ? 1.5 : 3.0;
    final w = math.max(1.0, (size.width - gap * (n - 1)) / n);
    for (var i = 0; i < n; i++) {
      final x = i * (w + gap);
      final isFuture = i >= elapsed;
      final h = top <= 0 ? 0.0 : values[i] / top * (size.height - 4) * grow;
      final r = Radius.circular(math.min(3, w / 2));
      if (isFuture || h < 2) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - 2, w, 2), r),
          Paint()..color = isFuture ? future : soft,
        );
        continue;
      }
      final sel = selected;
      final color = sel == null ? bar.withValues(alpha: 0.82) : (sel == i ? bar : soft);
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h, w, h), topLeft: r, topRight: r),
        Paint()..color = color,
      );
    }
    if (average > 0 && top > 0) {
      final y = size.height - average / top * (size.height - 4) * grow;
      final dash = Paint()
        ..color = guide
        ..strokeWidth = 1.2;
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3.5, size.width), y), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_DailyPainter old) =>
      old.values != values || old.selected != selected || old.grow != grow || old.bar != bar || old.elapsed != elapsed;
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.figure.copyWith(fontSize: 22)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.micro),
          ],
        ),
      ),
    );
  }
}
