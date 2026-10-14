import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/luxe_async.dart';
import '../../../shared/presentation/luxe_page.dart';
import '../domain/loan_calculator.dart';
import 'loan_ui.dart';

enum _Tab {
  active('Active'),
  closed('Closed');

  const _Tab(this.label);
  final String label;
}

/// Loans the user has borrowed or lent.
///
/// Top to bottom: the title; one obsidian card that answers "how much do I
/// owe, how far along am I, what is coming back and what is due soon"
/// (a payoff arc draws to the share already repaid); an overdue note when
/// needed; Active / Closed; then one card per loan with a one-tap
/// "record payment" when something is due within a week.
class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key});

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  _Tab _tab = _Tab.active;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(loansOverviewProvider);
    return LuxeDetailPage(
      title: 'Loans',
      storageKey: 'loans-list',
      actions: [
        LuxeIconButton(
          icon: LucideIcons.plus,
          tooltip: 'Add a loan',
          style: LuxeIconStyle.ink,
          size: 40,
          onPressed: () => context.push(AppRoutes.newLoan),
        ),
      ],
      slivers: [
        luxeBox(
          const Reveal(
            child: LuxePageTitle(
              eyebrow: 'Borrowed & lent',
              title: 'Loans',
              subtitle: 'Your balance moves only when you record a payment.',
            ),
          ),
          top: 4,
          bottom: 22,
        ),
        SliverToBoxAdapter(
          child: LuxeAsync<LoansOverview>(
            value: overview,
            loading: const LuxePageSkeleton(title: false, hero: 230, rows: 3),
            errorTitle: 'Could not load your loans',
            builder: (context, o) => _Body(overview: o, tab: _tab, onTab: (t) => setState(() => _tab = t)),
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.overview, required this.tab, required this.onTab});

  final LoansOverview overview;
  final _Tab tab;
  final ValueChanged<_Tab> onTab;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final items = tab == _Tab.active ? o.active : o.closed;
    final p = context.luxe;
    return ResponsiveCenter(
      padding: const EdgeInsets.symmetric(horizontal: LuxeSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!o.isEmpty) ...[
            Reveal(index: 1, scale: 0.97, child: _Hero(overview: o)),
            if (o.overdueCount > 0) ...[
              const SizedBox(height: 14),
              Reveal(
                index: 2,
                child: LuxeNote(
                  icon: LucideIcons.triangleAlert,
                  tone: p.warning,
                  message: o.overdueCount == 1
                      ? 'One loan has a payment past its due date. Record it once it is paid.'
                      : '${o.overdueCount} loans have payments past their due date. Record them once they are paid.',
                ),
              ),
            ],
            const SizedBox(height: 28),
            Reveal(
              index: 3,
              child: LuxeSegmented<_Tab>(
                segments: [
                  LuxeSegment(_Tab.active, _Tab.active.label, count: o.active.length),
                  LuxeSegment(_Tab.closed, _Tab.closed.label, count: o.closed.length),
                ],
                selected: tab,
                onChanged: onTab,
              ),
            ),
            const SizedBox(height: 16),
          ],
          AnimatedSwitcher(
            duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
            switchInCurve: LuxeCurves.arrive,
            switchOutCurve: LuxeCurves.leave,
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
            child: KeyedSubtree(
              key: ValueKey(tab),
              child: items.isEmpty
                  ? _Empty(overview: o, tab: tab)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Reveal(
                              index: 4 + i,
                              child: _LoanRow(state: items[i]),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.overview});

  final LoansOverview overview;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final o = overview;
    final borrowed = o.active.where((l) => l.loan.isBorrowed).length;
    final lent = o.active.length - borrowed;
    final share = o.borrowedRepaidShare;
    String count(int n, String noun) => n == 0 ? 'None active' : '$n $noun${n == 1 ? '' : 's'}';
    return LuxeObsidian(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LuxeFigure(
                  label: 'I owe',
                  onDark: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LuxeAmount(
                        o.borrowedOutstanding,
                        countFromZero: true,
                        style: t.display.copyWith(fontSize: 40, color: p.onObsidian),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        borrowed == 0 ? 'Nothing borrowed right now' : 'across ${count(borrowed, 'loan')}',
                        style: t.caption.c(p.onObsidianSoft),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _PayoffArc(share: share, empty: borrowed == 0),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(height: 1, child: ColoredBox(color: p.onObsidian.withValues(alpha: 0.1))),
          const SizedBox(height: 16),
          LuxeFigureRow(
            onDark: true,
            children: [
              LuxeFigure(
                label: 'Owed to me',
                onDark: true,
                child: _HeroValue(
                  amount: LuxeFigureAmount(
                    o.lentOutstanding,
                    onDark: true,
                    color: p.isDark ? p.positive : const Color(0xFF9BD3B5),
                  ),
                  caption: count(lent, 'loan'),
                ),
              ),
              LuxeFigure(
                label: 'Due in 30 days',
                onDark: true,
                child: _HeroValue(
                  amount: LuxeFigureAmount(o.dueIn30Days, onDark: true),
                  caption: o.dueIn30DaysCount == 0
                      ? 'Nothing due'
                      : '${o.dueIn30DaysCount} ${o.dueIn30DaysCount == 1 ? 'payment' : 'payments'} · projected',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroValue extends StatelessWidget {
  const _HeroValue({required this.amount, required this.caption});

  final Widget amount;
  final String caption;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      amount,
      const SizedBox(height: 2),
      Text(
        caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.lt.micro.c(context.luxe.onObsidianSoft),
      ),
    ],
  );
}

/// Half-ring gauge of the borrowed principal already repaid: ticks every
/// tenth, a champagne arc that draws in and a glowing head.
class _PayoffArc extends StatelessWidget {
  const _PayoffArc({required this.share, required this.empty});

  final double share;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final pct = (share * 100).round();
    return Semantics(
      label: empty ? 'No borrowed loans' : '$pct percent of borrowed principal repaid',
      excludeSemantics: true,
      child: SizedBox(
        width: 112,
        height: 74,
        child: DrawIn(
          value: empty ? 0 : share,
          delay: const Duration(milliseconds: 250),
          builder: (context, v) => CustomPaint(
            painter: _ArcPainter(
              value: v,
              track: p.onObsidian.withValues(alpha: 0.1),
              tick: p.onObsidian.withValues(alpha: 0.22),
              gradient: p.goldGradient.colors,
              head: p.gold,
            ),
            child: Align(
              alignment: const Alignment(0, 0.95),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    empty ? '—' : '${(v * 100).round()}%',
                    style: t.figure.copyWith(fontSize: 24, color: p.onObsidian),
                  ),
                  Text('REPAID', style: t.eyebrow.copyWith(fontSize: 9, color: p.onObsidianSoft)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.value,
    required this.track,
    required this.tick,
    required this.gradient,
    required this.head,
  });

  final double value;
  final Color track;
  final Color tick;
  final List<Color> gradient;
  final Color head;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final r = size.width / 2 - stroke;
    final c = Offset(size.width / 2, size.height - 4);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = track,
    );
    final tp = Paint()
      ..color = tick
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final a = math.pi + math.pi * i / 10;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r + 6), c + d * (r + (i % 5 == 0 ? 11 : 9)), tp);
    }
    if (value <= 0.002) return;
    canvas.drawArc(
      rect,
      math.pi,
      math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(startAngle: math.pi, endAngle: math.pi * 2, colors: gradient).createShader(rect),
    );
    final a = math.pi + math.pi * value;
    final h = c + Offset(math.cos(a), math.sin(a)) * r;
    canvas.drawCircle(h, 9, Paint()..color = head.withValues(alpha: 0.22));
    canvas.drawCircle(h, 4, Paint()..color = head);
  }

  @override
  bool shouldRepaint(_ArcPainter o) => o.value != value || o.track != track;
}

class _LoanRow extends StatelessWidget {
  const _LoanRow({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final id = state.loan.id;
    final days = state.daysUntilNextDue;
    final showPay = !state.isClosed && days != null && days <= 7;
    return KeyedSubtree(
      key: ValueKey(id),
      child: LoanCard(
        state: state,
        onTap: () => context.push(AppRoutes.loan(id)),
        onPay: showPay ? () => context.push(AppRoutes.payLoan(id)) : null,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.overview, required this.tab});

  final LoansOverview overview;
  final _Tab tab;

  @override
  Widget build(BuildContext context) {
    if (overview.isEmpty || tab == _Tab.active) {
      return LuxeEmpty(
        icon: LucideIcons.landmark,
        title: overview.isEmpty ? 'No loans yet' : 'No active loans',
        message:
            'Add a bank loan with EMIs, or money borrowed from or lent to family and friends. '
            'FiNN tracks what is left and what is due next.',
        actionLabel: 'Add a loan',
        actionIcon: LucideIcons.plus,
        onAction: () => context.push(AppRoutes.newLoan),
      );
    }
    return const LuxeEmpty(
      icon: LucideIcons.circleCheck,
      title: 'No closed loans',
      message: 'Loans you repay in full appear here with their history.',
    );
  }
}
