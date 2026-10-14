import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/luxe_async.dart';
import '../application/loan_actions.dart';
import '../domain/loan.dart';
import '../domain/loan_calculator.dart';
import 'loan_ui.dart';

enum _Menu { edit, delete }

/// One loan: what is left (a ring of what is repaid), the one action that
/// matters (record a payment), the next instalment split into interest and
/// principal, the payoff curve to zero, then terms, schedule and history.
class LoanDetailScreen extends ConsumerStatefulWidget {
  const LoanDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends ConsumerState<LoanDetailScreen> {
  final _key = newIdempotencyKey();

  Future<void> _menu(LoanState s) async {
    final hasPayments = s.payments.isNotEmpty;
    final choice = await showLuxeMenu<_Menu>(
      context,
      title: s.loan.name,
      eyebrow: 'Loan',
      items: [
        const LuxeMenuItem(
          value: _Menu.edit,
          label: 'Edit details',
          icon: LucideIcons.pencil,
          hint: 'Name, lender, rate and dates',
        ),
        LuxeMenuItem(
          value: _Menu.delete,
          label: 'Delete',
          icon: hasPayments ? LucideIcons.lock : LucideIcons.trash2,
          destructive: !hasPayments,
          hint: hasPayments ? 'Unavailable — payments exist' : null,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == _Menu.delete && hasPayments) {
      FinnToast.info(context, 'Loans with payments cannot be deleted, so your history stays accurate.');
      return;
    }
    switch (choice) {
      case _Menu.edit:
        context.push(AppRoutes.editLoan(s.loan.id));
      case _Menu.delete:
        final ok = await showLuxeConfirm(
          context,
          title: 'Delete ${s.loan.name}?',
          message: 'The loan and its schedule are removed. This cannot be undone.',
          confirmLabel: 'Delete',
          icon: LucideIcons.trash2,
          destructive: true,
        );
        if (!ok || !mounted) return;
        final done = await runAction(
          context,
          ref,
          action: const DeleteLoanAction(),
          input: LoanIdInput(id: s.loan.id),
          idempotencyKey: '$_key-del',
        );
        if (done != null && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(loanStateProvider(widget.id));
    final s = value.value;
    return LuxeDetailPage(
      title: s?.loan.name ?? 'Loan',
      storageKey: 'loan-${widget.id}',
      actions: [
        if (s != null)
          LuxeIconButton(
            icon: LucideIcons.ellipsis,
            tooltip: 'More actions',
            style: LuxeIconStyle.ghost,
            size: 40,
            onPressed: () => _menu(s),
          ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: LuxeAsync<LoanState?>(
            value: value,
            loading: const LuxePageSkeleton(hero: 250, rows: 3, controls: false),
            errorTitle: 'Could not load this loan',
            builder: (context, s) {
              if (s == null) {
                return LuxeEmpty(
                  icon: LucideIcons.searchX,
                  title: 'This loan no longer exists',
                  message: 'It may have been deleted.',
                  actionLabel: 'Back to loans',
                  onAction: () => context.go(AppRoutes.loans),
                );
              }
              return _Body(state: s);
            },
          ),
        ),
      ],
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.state});

  final LoanState state;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  static const _collapsedRows = 5;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final s = widget.state;
    final l = s.loan;
    final next = s.nextDue;
    final schedule = _showAll ? s.schedule : s.schedule.take(_collapsedRows).toList();
    var i = 0;
    Widget r(Widget child) => Reveal(index: i++, child: child);
    return ResponsiveCenter(
      padding: const EdgeInsets.symmetric(horizontal: LuxeSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          r(
            LuxeTitle(
              eyebrow: l.direction.pill,
              title: l.name,
              subtitle: '${l.counterparty} · ${l.structure.label} · ${l.rate.label} p.a.',
            ),
          ),
          const SizedBox(height: 20),
          Reveal(
            index: i++,
            scale: 0.97,
            child: _Hero(state: s),
          ),
          if (!s.isClosed) ...[
            const SizedBox(height: 14),
            r(
              LuxeButton(
                label: l.isBorrowed ? 'Record a payment' : 'Record money received',
                icon: LucideIcons.check,
                expand: true,
                onPressed: () => context.push(AppRoutes.payLoan(l.id)),
              ),
            ),
          ],
          if (s.warning != null) ...[
            const SizedBox(height: 14),
            r(LuxeNote(icon: LucideIcons.triangleAlert, tone: p.warning, message: s.warning!)),
          ],
          if (next != null) ...[const SizedBox(height: 14), r(_NextDueCard(state: s, row: next))],
          if (l.isAmortizing && !s.isClosed && s.schedule.length >= 2) ...[
            const SizedBox(height: 14),
            r(_PayoffCurve(state: s)),
          ],
          const SizedBox(height: LuxeSpace.section),
          r(const LuxeEyebrowHeader(label: 'Terms')),
          const SizedBox(height: 12),
          r(_Terms(state: s)),
          if (s.schedule.isNotEmpty && !s.isClosed) ...[
            const SizedBox(height: LuxeSpace.section),
            LuxeEyebrowHeader(
              label: 'Upcoming schedule',
              caption: l.isAmortizing
                  ? 'Projected · ${s.schedule.length} left · interest ${maskedAmount(context, s.projectedInterest)}'
                  : 'Projected · next ${s.schedule.length} ${l.frequency.unit}s',
            ),
            const SizedBox(height: 14),
            MotionAnimatedSize(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var k = 0; k < schedule.length; k++)
                    LuxeRailNode(
                      key: ValueKey('row-${schedule[k].number}'),
                      color: schedule[k].dueDate.isBefore(s.today) ? p.negative : p.gold,
                      hollow: !schedule[k].dueDate.isBefore(s.today),
                      first: k == 0,
                      last: k == schedule.length - 1 && s.schedule.length <= schedule.length,
                      child: _ScheduleRowTile(row: schedule[k], today: s.today),
                    ),
                ],
              ),
            ),
            if (s.schedule.length > _collapsedRows)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.only(left: 34),
                  child: LuxeShowMore(
                    expanded: _showAll,
                    total: s.schedule.length,
                    onToggle: () => setState(() => _showAll = !_showAll),
                  ),
                ),
              ),
          ],
          const SizedBox(height: LuxeSpace.section),
          LuxeEyebrowHeader(
            label: l.isBorrowed ? 'Payments' : 'Repayments received',
            caption: s.payments.isEmpty ? null : '${s.payments.length} recorded',
          ),
          const SizedBox(height: 14),
          if (s.payments.isEmpty)
            Text(
              l.isBorrowed
                  ? 'No payments recorded yet. Record each EMI or repayment when you make it.'
                  : 'Nothing received yet. Record repayments as they come in.',
              style: t.bodySoft,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var k = 0; k < s.payments.length; k++)
                  LuxeRailNode(
                    key: ValueKey(s.payments[k].id),
                    color: p.positive,
                    icon: LucideIcons.check,
                    first: k == 0,
                    last: k == s.payments.length - 1,
                    child: _PaymentRow(payment: s.payments[k]),
                  ),
              ],
            ),
          if (s.payments.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.lock, size: 13, color: p.inkMute),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Loans with payments cannot be deleted, and their terms are locked, so your history stays accurate.',
                    style: t.micro,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final s = state;
    final l = s.loan;
    final due = loanDueLabel(context, s);
    final share = s.repaidBps / 10000;
    return LuxeObsidian(
      semanticLabel:
          '${l.direction.sentence(l.counterparty)}. Outstanding ${MoneyFormatter.spoken(s.outstanding)}. ${due.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.direction.sentence(l.counterparty),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.label.c(p.onObsidianSoft),
                    ),
                    const SizedBox(height: 6),
                    LuxeAmount(
                      s.outstanding,
                      countFromZero: true,
                      decimals: DecimalDisplay.auto,
                      style: t.display.copyWith(fontSize: 40, color: p.onObsidian),
                    ),
                    const SizedBox(height: 2),
                    Text(s.isClosed ? 'Fully repaid' : 'outstanding principal', style: t.caption.c(p.onObsidianSoft)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              LuxeRing(
                value: share,
                color: p.gold,
                gradient: p.goldGradient.colors,
                track: p.onObsidian.withValues(alpha: 0.1),
                size: 86,
                stroke: 5,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${s.repaidBps ~/ 100}%', style: t.figure.copyWith(fontSize: 22, color: p.onObsidian)),
                    Text(
                      l.direction.repaidVerb.toUpperCase(),
                      style: t.eyebrow.copyWith(fontSize: 8.5, color: p.onObsidianSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: LuxeStatus(label: due.label, color: s.isClosed ? p.positive : p.gold, icon: due.icon),
          ),
          const SizedBox(height: 18),
          SizedBox(height: 1, child: ColoredBox(color: p.onObsidian.withValues(alpha: 0.1))),
          const SizedBox(height: 16),
          LuxeFigureRow(
            onDark: true,
            children: [
              LuxeFigure(
                label: 'Principal',
                onDark: true,
                child: LuxeFigureAmount(l.principal, onDark: true, size: 15),
              ),
              LuxeFigure(
                label: l.direction.repaidVerb,
                onDark: true,
                child: LuxeFigureAmount(s.principalRepaid, onDark: true, size: 15),
              ),
              LuxeFigure(
                label: 'Interest',
                onDark: true,
                child: LuxeFigureAmount(s.interestPaid, onDark: true, size: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The next instalment, with how it splits into interest and principal as
/// one two-tone line.
class _NextDueCard extends StatelessWidget {
  const _NextDueCard({required this.state, required this.row});

  final LoanState state;
  final ScheduleRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final l = state.loan;
    final due = loanDueLabel(context, state);
    final title = l.isAmortizing
        ? 'Next EMI · #${row.number}'
        : (row.isFinal ? 'Final payment' : 'Next interest · #${row.number}');
    final total = row.payment.paise == 0 ? 1 : row.payment.paise;
    final interestShare = (row.interest.paise / total).clamp(0.0, 1.0);
    return LuxeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LuxeIconDisc(icon: LucideIcons.calendarClock, color: due.color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.heading),
                    Text(
                      '${DateFormats.dayMonthYear.format(row.dueDate)} · ${DateFormats.dueIn(row.dueDate, state.today)}',
                      style: t.caption,
                    ),
                  ],
                ),
              ),
              LuxeAmount(row.payment, fit: false, style: t.figure.copyWith(fontSize: 24)),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            label:
                'Projected split: ${maskedAmount(context, row.interest)} interest, '
                '${maskedAmount(context, row.principal)} principal',
            excludeSemantics: true,
            child: SizedBox(
              height: 8,
              child: DrawIn(
                value: 1,
                builder: (context, v) => CustomPaint(
                  painter: _SplitPainter(
                    interest: interestShare * v,
                    principal: (1 - interestShare) * v,
                    interestColor: p.lineStrong,
                    principalColor: p.gold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Legend(color: p.gold, label: 'Principal', value: maskedAmount(context, row.principal)),
              const SizedBox(width: 16),
              _Legend(color: p.lineStrong, label: 'Interest', value: maskedAmount(context, row.interest)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$label '),
                  TextSpan(text: value, style: t.micro.w(750).c(context.luxe.ink)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.micro,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitPainter extends CustomPainter {
  _SplitPainter({
    required this.interest,
    required this.principal,
    required this.interestColor,
    required this.principalColor,
  });

  final double interest;
  final double principal;
  final Color interestColor;
  final Color principalColor;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    const gap = 3.0;
    final pw = math.max(0.0, w * principal - gap / 2);
    final iw = math.max(0.0, w * interest - gap / 2);
    final r = Radius.circular(h / 2);
    if (pw > 0) canvas.drawRRect(RRect.fromLTRBR(0, 0, pw, h, r), Paint()..color = principalColor);
    if (iw > 0) canvas.drawRRect(RRect.fromLTRBR(w - iw, 0, w, h, r), Paint()..color = interestColor);
  }

  @override
  bool shouldRepaint(_SplitPainter o) => o.interest != interest || o.principal != principal;
}

/// The outstanding balance after each remaining instalment, as a curve
/// that draws down to zero by the projected end date.
class _PayoffCurve extends StatelessWidget {
  const _PayoffCurve({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final s = state;
    final start = s.outstanding.paise.toDouble();
    final points = [start, for (final r in s.schedule) r.balanceAfter.paise.toDouble()];
    final end = s.projectedEndDate;
    return LuxeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Path to zero', style: t.heading)),
              if (end != null)
                Text('Debt-free ${DateFormats.shortMonthYear.format(end)}', style: t.micro.w(700).c(p.goldInk)),
            ],
          ),
          const SizedBox(height: 4),
          Text('${s.schedule.length} instalments left if you keep paying on time.', style: t.caption),
          const SizedBox(height: 16),
          Semantics(
            label: 'Outstanding balance falls to zero over ${s.schedule.length} instalments',
            excludeSemantics: true,
            child: SizedBox(
              height: 96,
              child: DrawIn(
                value: 1,
                delay: const Duration(milliseconds: 200),
                builder: (context, v) => CustomPaint(
                  painter: _CurvePainter(
                    points: points,
                    progress: v,
                    line: p.gold,
                    fill: p.gold,
                    grid: p.line,
                    dot: p.ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Today', style: t.micro),
              const Spacer(),
              Text(end == null ? 'End' : DateFormats.dayMonthYear.format(end), style: t.micro),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.points,
    required this.progress,
    required this.line,
    required this.fill,
    required this.grid,
    required this.dot,
  });

  final List<double> points;
  final double progress;
  final Color line;
  final Color fill;
  final Color grid;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final maxV = points.reduce(math.max);
    if (maxV <= 0) return;
    final w = size.width;
    final h = size.height - 6;
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = 3 + h * i / 2;
      for (var x = 0.0; x < w; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 2, y), gp);
      }
    }
    Offset at(int i) => Offset(w * i / (points.length - 1), 3 + h * (1 - points[i] / maxV));
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final a = at(i - 1);
      final b = at(i);
      final mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w * progress, size.height));
    final area = Path.from(path)
      ..lineTo(w, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fill.withValues(alpha: 0.22), fill.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = line,
    );
    canvas.restore();
    canvas.drawCircle(at(0), 4, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_CurvePainter o) => o.progress != progress || o.points.length != points.length;
}

class _Terms extends StatelessWidget {
  const _Terms({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    final s = state;
    final l = s.loan;
    Widget amount(Money m) =>
        LuxeAmount(m, fit: false, style: t.label.w(650).copyWith(fontFeatures: const [FontFeature.tabularFigures()]));
    final note = l.note?.trim() ?? '';
    return LuxeFacts(
      initiallyShown: 6,
      facts: [
        LuxeFact(l.isBorrowed ? 'Lender' : 'Borrower', value: l.counterparty),
        LuxeFact('Type', value: l.structure.label),
        LuxeFact('Principal', child: amount(l.principal)),
        LuxeFact('Interest rate', value: '${l.rate.label} p.a.'),
        LuxeFact('Repayment', value: l.frequency.label),
        LuxeFact(
          l.isAmortizing ? 'Current EMI' : 'Interest per ${l.frequency.unit}',
          child: amount(s.currentInstallment),
        ),
        LuxeFact('Started', value: DateFormats.dayMonthYear.format(l.startDate)),
        if (l.isAmortizing) ...[
          LuxeFact('Tenure', value: '${l.tenureInstallments ?? 0} instalments'),
          LuxeFact('Paid', value: '${s.periodsPaid} instalments'),
          if (!s.isClosed && s.remainingInstallments != null)
            LuxeFact('Remaining', value: '${s.remainingInstallments} instalments (projected)'),
          LuxeFact('After a prepayment', value: l.prepaymentStrategy.label),
        ],
        if (s.projectedEndDate != null && !s.isClosed)
          LuxeFact(
            l.isAmortizing ? 'Projected end' : 'Principal due',
            value: DateFormats.dayMonthYear.format(s.projectedEndDate!),
          ),
        if (!l.isAmortizing && l.maturityDate == null) const LuxeFact('Principal due', value: 'No fixed date'),
        LuxeFact(l.isBorrowed ? 'Interest paid' : 'Interest received', child: amount(s.interestPaid)),
        if (l.isAmortizing && !s.isClosed) LuxeFact('Total interest cost', child: amount(s.totalInterestCost)),
      ],
      footer: note.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NOTES', style: t.eyebrow),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: Text(note, style: t.body),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ScheduleRowTile extends StatelessWidget {
  const _ScheduleRowTile({required this.row, required this.today});

  final ScheduleRow row;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final overdue = row.dueDate.isBefore(today);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('#${row.number}', style: t.micro.w(800).c(p.goldInk)),
                      Text(DateFormats.dayMonthYear.format(row.dueDate), style: t.label.w(650).c(p.ink)),
                      if (overdue) LuxeStatus(label: 'Overdue', color: p.negative, icon: LucideIcons.triangleAlert),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${maskedAmount(context, row.interest)} interest · ${maskedAmount(context, row.principal)} principal',
                    style: t.micro,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('Balance after ${maskedAmount(context, row.balanceAfter)}', style: t.micro),
                ],
              ),
            ),
            const SizedBox(width: 8),
            LuxeAmount(row.payment, fit: false, style: t.number.copyWith(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final LoanPayment payment;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final pay = payment;
    final txId = pay.transactionId;
    final split = [
      if (pay.interestComponent.isPositive) '${maskedAmount(context, pay.interestComponent)} interest',
      if (pay.principalComponent.isPositive) '${maskedAmount(context, pay.principalComponent)} principal',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${pay.kind.label}${pay.periodNumber != null ? ' #${pay.periodNumber}' : ''}',
                  style: t.label.w(700).c(p.ink),
                ),
              ),
              LuxeAmount(pay.total, fit: false, style: t.number.copyWith(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [DateFormats.dayMonthYear.format(pay.date), if (split.isNotEmpty) split].join(' · '),
            style: t.caption,
            maxLines: 2,
          ),
          if (txId == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(LucideIcons.circleSlash, size: 12, color: p.inkMute),
                  const SizedBox(width: 6),
                  Flexible(child: Text('Not recorded as a cash movement', style: t.micro)),
                ],
              ),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Transform.translate(
                offset: const Offset(-12, 0),
                child: LuxeLink(
                  label: 'View linked transaction',
                  icon: LucideIcons.arrowUpRight,
                  onTap: () => context.push(AppRoutes.transaction(txId)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
