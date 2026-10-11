import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../domain/alert.dart';
import 'alert_visuals.dart';

/// Deep link for the record an alert points to.
String alertRoute(FinancialAlert a) {
  final id = a.recordId;
  return switch (a.target) {
    AlertTarget.loan => id == null ? AppRoutes.loans : AppRoutes.loan(id),
    AlertTarget.pending => id == null ? AppRoutes.pending : AppRoutes.pendingItem(id),
    AlertTarget.subscription => id == null ? AppRoutes.subscriptions : AppRoutes.subscription(id),
    AlertTarget.budget => id == null ? AppRoutes.budgets : AppRoutes.budget(id),
    AlertTarget.emergencyFund => AppRoutes.emergencyFund,
    AlertTarget.goal => id == null ? AppRoutes.goals : AppRoutes.goal(id),
    AlertTarget.transactions => AppRoutes.transactions,
  };
}

/// Colour and icon for a severity (never colour alone: the label is shown too).
extension AlertSeverityStyle on AlertSeverity {
  Color color(FinnColors c) => switch (this) {
    AlertSeverity.critical => c.negative,
    AlertSeverity.warning => c.attention,
    AlertSeverity.info => c.info,
    AlertSeverity.positive => c.positive,
  };

  Color soft(FinnColors c) => switch (this) {
    AlertSeverity.critical => c.negativeSoft,
    AlertSeverity.warning => c.attentionSoft,
    AlertSeverity.info => c.infoSoft,
    AlertSeverity.positive => c.positiveSoft,
  };

  IconData get icon => switch (this) {
    AlertSeverity.critical => LucideIcons.circleAlert,
    AlertSeverity.warning => LucideIcons.clock,
    AlertSeverity.info => LucideIcons.info,
    AlertSeverity.positive => LucideIcons.partyPopper,
  };
}

/// One "what needs attention" item, shown as a picture first: an animated
/// illustration of the numbers, one big figure, who or what it is about,
/// one or two status chips and a single action. The full sentences stay
/// available to screen readers.
class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.alert,
    this.unread = false,
    this.position,
    this.total,
    this.expand = false,
  });

  final FinancialAlert alert;

  /// Shows a small "New" marker.
  final bool unread;

  /// 1-based place in a carousel, shown as "2/5" with [total].
  final int? position;
  final int? total;

  /// Fill a fixed height (carousel) by pushing the action to the bottom.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final a = alert;
    final accent = a.severity.color(c);
    final hidden = AmountVisibility.hiddenOf(context);
    final face = _Face.of(a, c, hidden);
    final urgent = a.severity == AlertSeverity.critical;
    final pos = position, count = total;

    final header = Row(
      children: [
        _SeverityDot(color: accent, pulse: urgent),
        const SizedBox(width: Space.x1_5),
        Text(
          a.severity.label.toUpperCase(),
          style: t.eyebrow.copyWith(color: accent, fontWeight: FontWeight.w900),
        ),
        Flexible(
          child: Text('  ·  ${a.type.label}', style: t.micro, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const Spacer(),
        if (unread) ...[StatusPill(label: 'New', color: c.info, filled: true), const SizedBox(width: Space.x1_5)],
        if (pos != null && count != null && count > 1)
          Text('$pos/$count', style: t.micro.copyWith(fontWeight: FontWeight.w800)),
      ],
    );

    final visual = a.visual;
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(Space.x1_5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: c.isDark ? 0.14 : 0.07),
            borderRadius: Radii.rXl,
          ),
          child: visual == null
              ? SizedBox.square(dimension: 84, child: Icon(a.severity.icon, size: 36, color: accent))
              : AlertIllustration(visual: visual, accent: accent, size: 84),
        ),
        const SizedBox(width: Space.x3 + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  face.headline,
                  maxLines: 1,
                  style: t.amountLarge.copyWith(color: face.headlineColor ?? c.textPrimary, height: 1.1),
                ),
              ).maybeAnimate(
                context,
                (x) => x.fadeIn(delay: 150.ms, duration: 300.ms).slideX(begin: 0.08, curve: Curves2.emphasized),
              ),
              const SizedBox(height: Space.x1),
              Text(
                face.subline,
                style: t.bodyStrong.copyWith(color: c.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Space.x2),
              Wrap(
                spacing: Space.x1_5,
                runSpacing: Space.x1_5,
                children: [
                  for (var i = 0; i < face.chips.length; i++)
                    _Chip(chip: face.chips[i]).maybeAnimate(
                      context,
                      (x) => x
                          .fadeIn(delay: (300 + i * 90).ms, duration: 260.ms)
                          .scaleXY(begin: 0.85, curve: Curves.easeOutBack),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return PressableScale(
      haptic: true,
      onTap: () => context.push(alertRoute(a)),
      semanticLabel: hidden
          ? '${a.severity.label}. ${a.type.label}. ${a.actionLabel}.'
          : '${a.severity.label}. ${a.title}. ${a.message} ${a.reason} ${a.actionLabel}.',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: Radii.rXxl,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(accent.withValues(alpha: c.isDark ? 0.12 : 0.06), c.surface),
                c.surface,
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: c.isDark ? 0.35 : 0.22)),
            boxShadow: c.isDark ? Elevation.none : Elevation.md,
          ),
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3 + 2, Space.x4, Space.x3 + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              header,
              const SizedBox(height: Space.x3),
              if (expand)
                Expanded(
                  // Never overflow a fixed carousel height: shrink instead.
                  child: LayoutBuilder(
                    builder: (context, box) => Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(width: box.maxWidth, child: body),
                      ),
                    ),
                  ),
                )
              else
                body,
              const SizedBox(height: Space.x3),
              _ActionBar(label: a.actionLabel, color: accent, solid: urgent),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the card shows in place of sentences.
class _Face {
  const _Face(this.headline, this.subline, this.chips, {this.headlineColor});

  final String headline;
  final String subline;
  final List<_ChipData> chips;
  final Color? headlineColor;

  static _Face of(FinancialAlert a, FinnColors c, bool hidden) {
    String m(Money v) => hidden ? MoneyFormatter.masked : v.whole;
    String days(int n) => n == 1 ? '1 day' : '$n days';
    final amount = a.amount == null ? a.title : m(a.amount!);
    final v = a.visual;
    return switch (v) {
      DueVisual() => _Face(
        amount,
        v.recurring
            ? '${v.counterparty} renews'
            : v.outgoing
            ? 'Pay ${v.counterparty}'
            : 'Collect from ${v.counterparty}',
        [
          if (v.isLate)
            _ChipData(LucideIcons.alarmClock, '${days(-v.daysUntil)} late', c.negative)
          else
            _ChipData(LucideIcons.calendarClock, switch (v.daysUntil) {
              0 => 'Today',
              1 => 'Tomorrow',
              _ => 'In ${days(v.daysUntil)}',
            }, v.daysUntil <= 1 ? c.attention : c.info),
          _ChipData(
            v.outgoing ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft,
            v.outgoing ? 'Money out' : 'Money in',
            v.outgoing ? c.textSecondary : c.positive,
          ),
        ],
        headlineColor: v.isLate ? c.negative : null,
      ),
      AgedVisual() => _Face(amount, v.outgoing ? 'You owe ${v.counterparty}' : '${v.counterparty} owes you', [
        _ChipData(LucideIcons.hourglass, '${days(v.daysOpen)} pending', c.info),
        v.outgoing
            ? _ChipData(LucideIcons.arrowUpRight, 'Money out', c.textSecondary)
            : _ChipData(LucideIcons.arrowDownLeft, 'Money in', c.positive),
      ]),
      BudgetVisual() => _Face(
        v.isOver ? '${m(v.spent - v.limit)} over' : '${(v.fraction * 100).round()}% used',
        '${v.category} budget',
        [
          if (v.isOver)
            _ChipData(LucideIcons.ban, 'Limit crossed', c.negative)
          else
            _ChipData(LucideIcons.wallet, '${m(v.left)} left', c.attention),
          _ChipData(LucideIcons.calendarDays, '${days(v.daysLeft)} to go', c.textSecondary),
        ],
        headlineColor: v.isOver ? c.negative : null,
      ),
      SafetyNetVisual(isConfigured: false) => _Face('No safety net', 'Emergency fund', [
        _ChipData(LucideIcons.shieldOff, 'Not set up', c.info),
      ]),
      SafetyNetVisual() => _Face(
        '${(v.coverageMonths ?? 0).toStringAsFixed(1)} of ${v.targetMonths} months',
        'Emergency fund',
        [
          _ChipData(
            LucideIcons.target,
            '${m(Money.max(v.target! - (v.saved ?? Money.zero), Money.zero))} to go',
            c.attention,
          ),
        ],
      ),
      GoalVisual(isReached: true) => _Face('Goal reached!', v.name, [
        _ChipData(LucideIcons.piggyBank, '${m(v.saved)} saved', c.positive),
      ], headlineColor: c.positive),
      GoalVisual(isBehind: true) => _Face('${m(v.requiredMonthly!)}/mo', v.name, [
        _ChipData(LucideIcons.trendingDown, 'Behind plan', c.negative),
        if (v.targetDate != null)
          _ChipData(LucideIcons.flag, 'By ${DateFormats.shortMonthYear.format(v.targetDate!)}', c.textSecondary),
      ]),
      GoalVisual() => _Face('${(v.fraction * 100).round()}% there', v.name, [
        _ChipData(LucideIcons.target, '${m(Money.max(v.target - v.saved, Money.zero))} to go', c.positive),
      ], headlineColor: c.positive),
      CashFlowVisual() => _Face('${m(v.gap)} over', 'Spent more than earned', [
        _ChipData(LucideIcons.arrowDownLeft, 'In ${hidden ? MoneyFormatter.masked : v.income.compact}', c.positive),
        _ChipData(LucideIcons.arrowUpRight, 'Out ${hidden ? MoneyFormatter.masked : v.expense.compact}', c.negative),
      ], headlineColor: c.negative),
      null => _Face(a.title, a.type.label, const []),
    };
  }
}

class _ChipData {
  const _ChipData(this.icon, this.label, this.color);

  final IconData icon;
  final String label;
  final Color color;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.chip});

  final _ChipData chip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1),
      decoration: BoxDecoration(
        color: chip.color.withValues(alpha: c.isDark ? 0.18 : 0.1),
        borderRadius: Radii.rFull,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chip.icon, size: 12, color: chip.color),
          const SizedBox(width: Space.x1),
          Flexible(
            child: Text(
              chip.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.micro.copyWith(color: chip.color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Severity dot; urgent alerts send out a few radar pulses.
class _SeverityDot extends StatelessWidget {
  const _SeverityDot({required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!pulse || context.reduceMotion) return dot;
    return SizedBox.square(
      dimension: 8,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              )
              .animate(onPlay: (ctl) => ctl.repeat(count: 4))
              .scaleXY(begin: 1, end: 2.8, duration: 1100.ms, curve: Curves.easeOut)
              .fadeOut(duration: 1100.ms),
          dot,
        ],
      ),
    );
  }
}

/// The single next step, styled as a button (the whole card is the target).
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.label, required this.color, required this.solid});

  final String label;
  final Color color;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = solid ? Colors.white : color;
    Widget bar = Container(
      height: 44,
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: c.isDark ? 0.2 : 0.11),
        borderRadius: Radii.rLg,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.label.copyWith(color: fg, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: Space.x1_5),
          Icon(LucideIcons.arrowRight, size: 16, color: fg).maybeAnimate(
            context,
            (x) => x
                .moveX(delay: 900.ms, end: 4, duration: 280.ms, curve: Curves.easeOut)
                .then()
                .moveX(end: -4, duration: 280.ms, curve: Curves.easeIn)
                .then()
                .moveX(end: 4, duration: 280.ms, curve: Curves.easeOut)
                .then()
                .moveX(end: -4, duration: 280.ms, curve: Curves.easeIn),
          ),
        ],
      ),
    );
    if (solid) {
      bar = bar.maybeAnimate(
        context,
        (x) => x.shimmer(delay: 700.ms, duration: 1200.ms, color: Colors.white.withValues(alpha: 0.35)),
      );
    }
    return bar;
  }
}
