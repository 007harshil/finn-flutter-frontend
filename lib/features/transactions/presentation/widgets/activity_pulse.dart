import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
import '../../../categories/domain/category.dart';
import '../../application/transaction_filter.dart';
import '../../domain/transaction.dart';

/// Ids of the non-category parts of the money bar.
const String _otherId = '_other';
const String _keptId = '_kept';

/// Most categories named in the bar; the rest fold into "Other".
const int _barCategories = 4;

/// Compact, plain-language summary of the filtered Activity list.
///
/// One sentence answers "how did this period go?" ("Kept ₹54,916 · 44% of
/// income"); one bar shows where the money went: income is the full width,
/// each spending category takes its share and whatever is left is kept.
/// Tapping a slice or legend chip filters the list to that category.
/// "Details" opens a daily spend chart you can scrub, plus three quick
/// facts. All motion is finite and skipped under reduced motion.
class ActivityPulse extends ConsumerStatefulWidget {
  const ActivityPulse({super.key, required this.feed});

  final TransactionFeed feed;

  @override
  ConsumerState<ActivityPulse> createState() => _ActivityPulseState();
}

class _ActivityPulseState extends ConsumerState<ActivityPulse> {
  static const _storageKey = 'activity-pulse-expanded';
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final feed = widget.feed;
    final f = feed.filter;
    final cats = ref.watch(categoriesByIdProvider).value ?? const <String, TransactionCategory>{};
    final today = ref.watch(todayProvider);
    final incomeMode = f.type == TransactionType.income;
    final story = _Story.of(feed, incomeMode);
    final bar = _BarModel.of(feed, cats, incomeMode, c);

    return FinnCard(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x3),
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
              _DeltaChip(feed: feed, incomeMode: incomeMode, today: today),
            ],
          ),
          const SizedBox(height: Space.x2),
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
                        style: t.caption.copyWith(color: c.textSecondary, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      AnimatedAmount(
                        story.amount,
                        decimals: DecimalDisplay.none,
                        fit: true,
                        animateOnMount: true,
                        style: t.amountMedium.copyWith(color: story.color(c)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Space.x3),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Flow(icon: LucideIcons.arrowDownLeft, label: 'In', amount: feed.income, color: c.positive),
                  const SizedBox(height: 2),
                  _Flow(icon: LucideIcons.arrowUpRight, label: 'Out', amount: -feed.expense, color: c.negative),
                ],
              ),
            ],
          ),
          if (bar.total > 0) ...[
            const SizedBox(height: Space.x2_5),
            RepaintBoundary(
              child: _MoneyBar(
                model: bar,
                selected: f.categoryIds,
                semanticLabel: bar.semantics(cats),
                onTapCategory: _toggleCategory,
              ),
            ),
          ],
          const SizedBox(height: Space.x2),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in bar.legend) ...[
                        _LegendChip(
                          key: ValueKey('pulse-legend:${s.id}'),
                          label: cats[s.id]?.name ?? 'Other',
                          percent: bar.percentOf(s),
                          color: s.color,
                          selected: f.categoryIds.contains(s.id),
                          onTap: () => _toggleCategory(s.id),
                        ),
                        const SizedBox(width: Space.x1_5),
                      ],
                    ],
                  ),
                ),
              ),
              _DetailsButton(expanded: _expanded, onTap: _toggle),
            ],
          ),
          MotionAnimatedSize(
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: Space.x3),
                    child: _Details(feed: feed, today: today, cats: cats),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  void _toggleCategory(String id) {
    HapticFeedback.selectionClick();
    ref.read(transactionFilterProvider.notifier).toggleCategory(id);
  }
}

String _periodShort(TransactionFilter f) {
  if (!f.hasCustomRange) return DateFormats.monthYear.format(f.month.start);
  final r = f.range;
  final start = r.start.year == r.end.year ? DateFormats.dayMonth.format(r.start) : DateFormats.dayMonthYear.format(r.start);
  return '$start – ${DateFormats.dayMonthYear.format(r.end)}';
}

String _money(BuildContext context, Money m, {bool compact = false}) {
  if (AmountVisibility.hiddenOf(context)) return MoneyFormatter.masked;
  return compact ? MoneyFormatter.compact(m) : MoneyFormatter.format(m, decimals: DecimalDisplay.none);
}

// ---------------------------------------------------------------------------
// Headline
// ---------------------------------------------------------------------------

enum _Outcome { kept, overspent, spent, earned, quiet }

/// The one-line verdict for the period.
@immutable
class _Story {
  const _Story(this.outcome, this.amount, this.caption);

  final _Outcome outcome;
  final Money amount;
  final String caption;

  Color color(FinnColors c) => switch (outcome) {
        _Outcome.kept || _Outcome.earned => c.positive,
        _Outcome.overspent => c.negative,
        _Outcome.spent || _Outcome.quiet => c.textPrimary,
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
    final t = context.text;
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(label, style: t.micro.copyWith(color: context.colors.textSecondary)),
          const SizedBox(width: Space.x1),
          AnimatedAmount(
            amount,
            sign: amount.isZero ? SignDisplay.auto : SignDisplay.always,
            decimals: DecimalDisplay.none,
            style: t.caption.copyWith(color: amount.isZero ? null : color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// "↓ 12% vs Sep": spending (or income) against the comparison period.
class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.feed, required this.incomeMode, required this.today});

  final TransactionFeed feed;
  final bool incomeMode;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = incomeMode ? feed.income : feed.expense;
    final before = incomeMode ? feed.previousIncome : feed.previousExpense;
    if (before.isZero || now.isZero) return const SizedBox.shrink();
    final pct = ((now.paise - before.paise) * 100 / before.paise).round();
    final f = feed.filter;
    final vs = f.hasCustomRange ? 'prev. period' : DateFormats.shortMonth.format(f.month.previous.start);
    final up = pct > 0;
    final good = incomeMode ? up : !up;
    final color = pct == 0 ? c.textSecondary : (good ? c.positive : c.negative);
    final what = incomeMode ? 'Income' : 'Spending';
    final label = pct == 0 ? 'Same as $vs' : '${pct.abs()}% vs $vs';
    final spoken = pct == 0
        ? '$what same as $vs'
        : '$what ${pct.abs()} percent ${up ? 'higher' : 'lower'} than $vs'
            '${!f.hasCustomRange && f.month.contains(today) ? ' at this point' : ''}';
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: Radii.rFull),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(pct == 0 ? LucideIcons.equal : (up ? LucideIcons.trendingUp : LucideIcons.trendingDown),
                size: 12, color: color),
            const SizedBox(width: Space.x1),
            Text('$what $label', style: context.text.micro.copyWith(color: color, fontWeight: FontWeight.w800)),
          ],
        ),
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

/// What the bar draws: [segments] share [total]; [marker] (0–1) marks where
/// income ends when spending exceeds it.
@immutable
class _BarModel {
  const _BarModel(this.segments, this.total, this.marker, this.base);

  final List<_Seg> segments;
  final double total;
  final double? marker;

  /// Amount percentages are quoted against (income when there is income).
  final double base;

  List<_Seg> get legend => segments.where((s) => s.id != _keptId).take(3).toList();

  int percentOf(_Seg s) => base <= 0 ? 0 : (s.value * 100 / base).round();

  static _BarModel of(TransactionFeed feed, Map<String, TransactionCategory> cats, bool incomeMode, FinnColors c) {
    final shares = incomeMode ? feed.incomeByCategory : feed.expenseByCategory;
    final segs = <_Seg>[];
    var rest = 0.0;
    for (var i = 0; i < shares.length; i++) {
      final s = shares[i];
      if (i < _barCategories) {
        segs.add(_Seg(s.categoryId, s.amount.paise.toDouble(), AccentSwatches.solid(cats[s.categoryId]?.colorIndex ?? 6)));
      } else {
        rest += s.amount.paise;
      }
    }
    if (rest > 0) segs.add(_Seg(_otherId, rest, c.textTertiary));
    final inc = feed.income.paise.toDouble();
    final exp = feed.expense.paise.toDouble();
    if (incomeMode) return _BarModel(segs, inc, null, inc);
    if (inc <= 0) return _BarModel(segs, exp, null, exp);
    if (inc > exp) segs.add(_Seg(_keptId, inc - exp, c.positive));
    return _BarModel(segs, math.max(inc, exp), exp > inc ? inc / exp : null, inc);
  }

  String semantics(Map<String, TransactionCategory> cats) {
    final parts = [
      for (final s in segments)
        '${s.id == _keptId ? 'Kept' : (cats[s.id]?.name ?? 'Other')} ${percentOf(s)} percent',
    ];
    return 'Where the money went: ${parts.join(', ')}';
  }
}

class _MoneyBar extends StatefulWidget {
  const _MoneyBar({
    required this.model,
    required this.selected,
    required this.semanticLabel,
    required this.onTapCategory,
  });

  final _BarModel model;
  final Set<String> selected;
  final String semanticLabel;
  final ValueChanged<String> onTapCategory;

  @override
  State<_MoneyBar> createState() => _MoneyBarState();
}

class _MoneyBarState extends State<_MoneyBar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);
  Map<String, double> _from = const {};
  bool _entrance = true;
  bool _started = false;

  Map<String, double> _fractions(_BarModel m) =>
      {for (final s in m.segments) s.id: m.total <= 0 ? 0 : s.value / m.total};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl.duration = context.motion.progress;
    if (!_started) {
      _started = true;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(_MoneyBar old) {
    super.didUpdateWidget(old);
    final next = _fractions(widget.model);
    final prev = _fractions(old.model);
    if (mapEquals(next, prev)) return;
    // Morph from wherever the bar is right now.
    final v = Curves2.emphasized.transform(_ctrl.value);
    _from = {
      for (final id in {..._from.keys, ...prev.keys}) id: ui.lerpDouble(_from[id] ?? 0, prev[id] ?? 0, v)!,
    };
    _entrance = false;
    _ctrl.duration = context.motion.slow;
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap(TapUpDetails d, double width) {
    if (width <= 0) return;
    final x = d.localPosition.dx / width;
    var acc = 0.0;
    for (final s in widget.model.segments) {
      acc += widget.model.total <= 0 ? 0 : s.value / widget.model.total;
      if (x <= acc) {
        if (s.isCategory) widget.onTapCategory(s.id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final to = _fractions(widget.model);
    final colors = {
      for (final s in widget.model.segments) s.id: s.color,
    };
    // Shrinking parts that left the bar keep drawing until they reach 0.
    final order = [
      for (final s in widget.model.segments)
        if (s.id != _keptId) s.id,
      for (final id in _from.keys)
        if (!to.containsKey(id) && id != _keptId) id,
      _keptId,
    ];
    return Semantics(
      label: widget.semanticLabel,
      hint: 'Tap a colour to filter by that category',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _onTap(d, box.maxWidth),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final v = Curves2.emphasized.transform(_ctrl.value);
              return CustomPaint(
                size: Size(box.maxWidth, 20),
                painter: _MoneyBarPainter(
                  order: order,
                  widths: {
                    for (final id in order) id: ui.lerpDouble(_from[id] ?? 0, to[id] ?? 0, v)!,
                  },
                  colors: colors,
                  selected: widget.selected,
                  marker: widget.model.marker,
                  markerT: v,
                  shine: _entrance && !context.reduceMotion ? _ctrl.value : null,
                  track: c.surfaceMuted,
                  keptColor: c.positive,
                  markerColor: c.textPrimary,
                  fallback: c.textTertiary,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MoneyBarPainter extends CustomPainter {
  _MoneyBarPainter({
    required this.order,
    required this.widths,
    required this.colors,
    required this.selected,
    required this.marker,
    required this.markerT,
    required this.shine,
    required this.track,
    required this.keptColor,
    required this.markerColor,
    required this.fallback,
  });

  final List<String> order;
  final Map<String, double> widths;
  final Map<String, Color> colors;
  final Set<String> selected;
  final double? marker;
  final double markerT;
  final double? shine;
  final Color track;
  final Color keptColor;
  final Color markerColor;
  final Color fallback;

  static const double _barH = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - _barH) / 2;
    final bar = RRect.fromRectAndRadius(Rect.fromLTWH(0, top, size.width, _barH), const Radius.circular(_barH / 2));
    canvas.drawRRect(bar, Paint()..color = track);
    canvas.save();
    canvas.clipRRect(bar);
    var x = 0.0;
    final dim = selected.isNotEmpty;
    for (final id in order) {
      final w = (widths[id] ?? 0) * size.width;
      if (w <= 0.2) continue;
      final rect = Rect.fromLTWH(x, top, w, _barH);
      if (id == _keptId) {
        canvas.drawRect(rect, Paint()..color = keptColor.withValues(alpha: 0.18));
        // Diagonal hatching: "money still with you".
        final hatch = Paint()
          ..color = keptColor.withValues(alpha: dim ? 0.25 : 0.55)
          ..strokeWidth = 2;
        canvas.save();
        canvas.clipRect(rect);
        for (var hx = rect.left - _barH; hx < rect.right; hx += 6) {
          canvas.drawLine(Offset(hx, top + _barH), Offset(hx + _barH, top), hatch);
        }
        canvas.restore();
      } else {
        final base = colors[id] ?? fallback;
        final on = !dim || selected.contains(id);
        canvas.drawRect(rect, Paint()..color = on ? base : base.withValues(alpha: 0.28));
      }
      x += w;
      // Hairline gap between parts.
      canvas.drawRect(Rect.fromLTWH(x - 1, top, 1.5, _barH), Paint()..color = track);
    }
    final s = shine;
    if (s != null && s > 0.45 && s < 1) {
      final p = (s - 0.45) / 0.55;
      const band = 48.0;
      final sx = -band + p * (size.width + band * 2);
      canvas.drawRect(
        Rect.fromLTWH(sx - band, top, band * 2, _barH),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(sx - band, 0),
            Offset(sx + band, 0),
            [const Color(0x00FFFFFF), const Color(0x59FFFFFF), const Color(0x00FFFFFF)],
            [0, 0.5, 1],
          ),
      );
    }
    canvas.restore();

    final m = marker;
    if (m != null) {
      // Where income ran out.
      final mx = (m * size.width).clamp(1.0, size.width - 1);
      canvas.drawLine(
        Offset(mx, size.height / 2 - (size.height / 2) * markerT),
        Offset(mx, size.height / 2 + (size.height / 2) * markerT),
        Paint()
          ..color = markerColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_MoneyBarPainter old) => true;
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    super.key,
    required this.label,
    required this.percent,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int percent;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $percent percent. ${selected ? 'Remove filter' : 'Show only $label'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: context.motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: Radii.rFull,
            border: Border.all(color: selected ? color : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: Space.x1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.micro.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: Space.x1),
              Text('$percent%', style: t.micro.copyWith(color: c.textSecondary, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsButton extends StatelessWidget {
  const _DetailsButton({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      expanded: expanded,
      label: expanded ? 'Hide daily details' : 'Show daily details',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('pulse-details'),
        onTap: onTap,
        borderRadius: Radii.rFull,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x2, Space.x1_5, Space.x1, Space.x1_5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                expanded ? 'Less' : 'Daily',
                style: context.text.micro.copyWith(color: c.primary, fontWeight: FontWeight.w800),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: context.motion.normal,
                curve: Curves2.emphasized,
                child: Icon(LucideIcons.chevronDown, size: 14, color: c.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Details: daily spend chart + quick facts
// ---------------------------------------------------------------------------

class _Details extends StatefulWidget {
  const _Details({required this.feed, required this.today, required this.cats});

  final TransactionFeed feed;
  final DateTime today;
  final Map<String, TransactionCategory> cats;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  int? _scrub;

  DateRange get _range => widget.feed.filter.range;

  /// Days per bar: one bar per day up to two months, then grouped.
  int get _bucket {
    final days = _range.dayCount;
    return days <= 62 ? 1 : (days / 40).ceil();
  }

  /// Days of the period that have already happened.
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
    final c = context.colors;
    final t = context.text;
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
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: context.motion.fast,
                layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
                child: Text(
                  heading,
                  key: ValueKey(heading),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption.copyWith(color: c.textPrimary, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Text(
              headingValue,
              style: t.micro.copyWith(
                color: scrub == null ? c.textTertiary : c.negative,
                fontWeight: scrub == null ? FontWeight.w600 : FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x1_5),
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
                child: _GrowIn(
                  builder: (context, g) => CustomPaint(
                    size: Size(box.maxWidth, 56),
                    painter: _DailyBarsPainter(
                      values: values,
                      elapsed: elapsedBuckets,
                      average: avgBucket,
                      selected: scrub,
                      grow: g,
                      bar: c.negative,
                      future: c.border,
                      guide: c.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.x3),
        Row(
          children: [
            Expanded(
              child: _Fact(
                icon: LucideIcons.gauge,
                label: 'Per day',
                value: _money(context, perDay, compact: true),
              ),
            ),
            Expanded(
              child: _Fact(
                icon: LucideIcons.flame,
                label: largestName == null ? 'Biggest' : 'Biggest · $largestName',
                value: largest == null ? '—' : _money(context, largest.amount, compact: true),
              ),
            ),
            Expanded(
              child: _Fact(
                icon: LucideIcons.leaf,
                label: 'No-spend days',
                value: '$noSpend of $elapsed',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 0 → 1 once on first build (instant under reduced motion).
class _GrowIn extends StatelessWidget {
  const _GrowIn({required this.builder});

  final Widget Function(BuildContext context, double t) builder;

  @override
  Widget build(BuildContext context) {
    final m = context.motion;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: m.reduced ? 1 : 0, end: 1),
      duration: m.progress,
      curve: Curves.linear,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

class _DailyBarsPainter extends CustomPainter {
  _DailyBarsPainter({
    required this.values,
    required this.elapsed,
    required this.average,
    required this.selected,
    required this.grow,
    required this.bar,
    required this.future,
    required this.guide,
  });

  final List<double> values;
  final int elapsed;
  final double average;
  final int? selected;
  final double grow;
  final Color bar;
  final Color future;
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final maxV = math.max(values.fold<double>(0, math.max), average);
    final slot = size.width / n;
    final gap = math.min(3.0, slot * 0.3);
    final w = math.max(1.5, slot - gap);
    final paint = Paint();
    for (var i = 0; i < n; i++) {
      final x = i * slot + gap / 2;
      if (i >= elapsed) {
        // Days still to come: a faint dot on the baseline.
        paint.color = future;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - 2, w, 2), const Radius.circular(1)),
          paint,
        );
        continue;
      }
      // Bars rise left to right, like the days passing.
      final local = Curves2.emphasized.transform(((grow - i / n * 0.4) / 0.6).clamp(0.0, 1.0));
      final h = maxV <= 0 || values[i] <= 0 ? 2.0 : math.max(3.0, (size.height - 4) * values[i] / maxV * local);
      final sel = selected == i;
      paint.color = values[i] <= 0
          ? future
          : (selected == null ? bar.withValues(alpha: 0.55) : (sel ? bar : bar.withValues(alpha: 0.25)));
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, size.height - h, w, h),
          topLeft: Radius.circular(math.min(3, w / 2)),
          topRight: Radius.circular(math.min(3, w / 2)),
        ),
        paint,
      );
    }
    if (average > 0 && maxV > 0) {
      final y = size.height - (size.height - 4) * average / maxV * grow;
      final dash = Paint()
        ..color = guide
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, size.width), y), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_DailyBarsPainter old) =>
      old.grow != grow ||
      old.selected != selected ||
      old.average != average ||
      old.elapsed != elapsed ||
      !listEquals(old.values, values) ||
      old.bar != bar;
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(right: Space.x2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: c.textTertiary),
                const SizedBox(width: Space.x1),
                Expanded(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.micro.copyWith(color: c.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(value, maxLines: 1, style: t.caption.copyWith(color: c.textPrimary, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
