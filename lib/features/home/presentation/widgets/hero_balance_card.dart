import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../design_system/design_system.dart'
    show FinnButton, FinnDivider, FinnSheetScaffold, InfoBanner, KeyValueRow;
import '../../../../finance/ledger.dart';
import '../../../../kit/kit.dart';
import '../../../../shared/presentation/async_view.dart';
import 'accounts_section.dart';

/// "Available to spend": the one number Home exists for, on the deep teal
/// slab. Under it, a bar of your cash with the free part in bright teal
/// and the set-aside part in a lighter tone, and the two amounts that
/// explain the gap. Tapping
/// "Set aside" splits it into goals and emergency fund; tapping the number
/// opens the full maths. Below that, the accounts the money sits in, as
/// a sideways strip of tiles ([HeroAccountsStrip]).
class HeroBalanceCard extends ConsumerWidget {
  const HeroBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<BalanceSnapshot>(
      value: ref.watch(balanceProvider),
      loading: const _BalanceSkeleton(),
      builder: (context, b) => _Balance(balance: b),
    );
  }
}

class _Balance extends StatefulWidget {
  const _Balance({required this.balance});

  final BalanceSnapshot balance;

  @override
  State<_Balance> createState() => _BalanceState();
}

class _BalanceState extends State<_Balance> {
  static const _inset = Sp.lg + 4;

  bool _split = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _split = !_split);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final b = widget.balance;
    final hidden = AmountVisibility.hiddenOf(context);
    final over = b.available.isNegative;
    // The bar is cash. When more is set aside than there is cash, the
    // set-aside parts fill it and the overage is called out in words.
    final base = over ? b.earmarked.paise : b.cash.paise;
    double share(Money m) => base <= 0 ? 0 : (m.paise / base).clamp(0.0, 1.0);
    final free = over ? 0.0 : share(b.available);
    final parts = _split
        ? [
            BarPart(free, c.flow),
            BarPart(share(b.earmarkedGoals), _Slab.goals),
            BarPart(share(b.earmarkedEmergency), _Slab.faint),
          ]
        : [BarPart(free, c.flow), BarPart(share(b.earmarked), _Slab.faint)];

    final slab = Container(
      decoration: BoxDecoration(gradient: c.deepGradient, borderRadius: Rad.rXl),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: const _FlowMarks(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(_inset, Sp.lg + 2, _inset, Sp.lg + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    button: true,
                    label: 'Available to spend. Double tap for how it adds up.',
                    child: InkWell(
                      borderRadius: Rad.rMd,
                      splashColor: Colors.white.withValues(alpha: 0.08),
                      highlightColor: Colors.white.withValues(alpha: 0.04),
                      onTap: () => showFinnSheet<void>(context, builder: (_) => BalanceBreakdownSheet(balance: b)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Available to spend',
                                  style: t.label.copyWith(color: _Slab.soft),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: Sp.xs + 2),
                              const Icon(LucideIcons.info, size: 15, color: _Slab.soft),
                            ],
                          ),
                          const SizedBox(height: Sp.xs),
                          AnimatedAmount(
                            b.available,
                            style: t.figureXL.copyWith(color: over && !hidden ? _Slab.over : _Slab.ink),
                            decimals: DecimalDisplay.none,
                            fit: true,
                            animateOnMount: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Sp.lg),
                  LedgerStackBar(
                    parts: parts,
                    gapColor: c.deep,
                    semanticLabel: hidden ? null : '${(free * 100).round()} percent of your cash is free to spend',
                  ),
                  const SizedBox(height: Sp.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _split
                        ? [
                            Expanded(
                              child: _Legend(
                                label: 'For goals',
                                amount: b.earmarkedGoals,
                                dot: _Slab.goals,
                                onTap: _toggle,
                              ),
                            ),
                            const SizedBox(width: Sp.lg),
                            Expanded(
                              child: _Legend(
                                label: 'Emergency fund',
                                amount: b.earmarkedEmergency,
                                dot: _Slab.faint,
                                end: true,
                                onTap: _toggle,
                                toggle: LucideIcons.chevronUp,
                              ),
                            ),
                          ]
                        : [
                            Expanded(
                              child: _Legend(label: 'Cash', amount: b.cash, dot: c.flow),
                            ),
                            const SizedBox(width: Sp.lg),
                            Expanded(
                              child: _Legend(
                                label: 'Set aside',
                                amount: b.earmarked,
                                dot: _Slab.faint,
                                end: true,
                                onTap: b.earmarked.isPositive ? _toggle : null,
                                toggle: b.earmarked.isPositive ? LucideIcons.chevronDown : null,
                              ),
                            ),
                          ],
                  ),
                  if (b.creditOwed.isPositive) ...[
                    const SizedBox(height: Sp.md),
                    Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
                    const SizedBox(height: Sp.md - 2),
                    MergeSemantics(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Credit card owed',
                              style: t.label.copyWith(color: _Slab.soft),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: Sp.sm),
                          AmountText(
                            b.creditOwed,
                            style: t.figureSmall.copyWith(color: _Slab.over),
                            decimals: DecimalDisplay.none,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const HeroAccountsStrip(inset: _inset),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        slab,
        if (over && !hidden) ...[
          const SizedBox(height: Sp.md),
          LedgerNote(
            tone: NoteTone.alert,
            icon: LucideIcons.triangleAlert,
            text:
                '${MoneyFormatter.format(-b.available, decimals: DecimalDisplay.none)} more is set aside than you have in cash.',
          ),
        ],
      ],
    );
  }
}

/// Dot, label and amount under the bar. Tappable ones toggle the split.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.label,
    required this.amount,
    required this.dot,
    this.end = false,
    this.onTap,
    this.toggle,
  });

  final String label;
  final Money amount;
  final Color dot;
  final bool end;
  final VoidCallback? onTap;
  final IconData? toggle;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final ic = toggle;
    final body = Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: Sp.xs + 2),
            Flexible(
              child: Text(
                label,
                style: t.label.copyWith(color: _Slab.soft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (ic != null) ...[const SizedBox(width: 2), Icon(ic, size: 15, color: _Slab.soft)],
          ],
        ),
        const SizedBox(height: 2),
        AmountText(
          amount,
          style: t.figure.copyWith(fontSize: 17, color: _Slab.ink),
          decimals: DecimalDisplay.none,
          fit: true,
          textAlign: end ? TextAlign.end : null,
        ),
      ],
    );
    final tap = onTap;
    if (tap == null) return MergeSemantics(child: body);
    return Semantics(
      button: true,
      hint: 'Splits set-aside money into goals and emergency fund',
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: tap, child: body),
    );
  }
}

/// Text and marks on the deep slab (the same in light and dark mode).
abstract final class _Slab {
  static const ink = Color(0xFFFFFFFF);
  static const soft = Color(0xD9FFFFFF);
  static const faint = Color(0x52FFFFFF);
  static const goals = Color(0xFFB9EBE4);
  static const over = Color(0xFFFFA494);
}

/// Two faint arcs in the slab's corner, after the flowing arrows of the
/// FiNN mark.
class _FlowMarks extends CustomPainter {
  const _FlowMarks();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x14FFFFFF);
    final r = size.height * 0.9;
    final centre = Offset(size.width + r * 0.18, -r * 0.1);
    canvas.drawCircle(centre, r * 0.62, paint..strokeWidth = 18);
    canvas.drawCircle(centre, r * 0.92, paint..strokeWidth = 10);
  }

  @override
  bool shouldRepaint(_FlowMarks old) => false;
}

class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return const LedgerSkeleton(height: 320, radius: Rad.xl);
  }
}

/// Explains how "available to spend" is derived from the ledger.
class BalanceBreakdownSheet extends StatelessWidget {
  const BalanceBreakdownSheet({super.key, required this.balance});

  final BalanceSnapshot balance;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    Widget line(String label, Money amount, {SignDisplay sign = SignDisplay.auto, bool strong = false, Color? color}) {
      return KeyValueRow(
        label: label,
        valueWidget: AmountText(
          amount,
          sign: sign,
          color: color,
          style: strong ? t.figure : t.figureSmall.copyWith(color: c.ink),
        ),
      );
    }

    return FinnSheetScaffold(
      title: 'How your balance adds up',
      description: 'Set-aside money is still yours. It is earmarked so you do not spend it by accident.',
      footer: FinnButton(label: 'Got it', expand: true, onPressed: () => Navigator.of(context).maybePop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line('Opening balance', balance.openingBalance),
          line('Money in', balance.totalInflow, sign: SignDisplay.always, color: c.green),
          line('Money out', -balance.totalOutflow, sign: SignDisplay.always),
          const FinnDivider(),
          line('Cash', balance.cash, strong: true),
          line('Set aside for goals', -balance.earmarkedGoals, sign: SignDisplay.always),
          line('Set aside for emergencies', -balance.earmarkedEmergency, sign: SignDisplay.always),
          const FinnDivider(),
          line('Available to spend', balance.available, strong: true),
          const SizedBox(height: Sp.lg),
          const InfoBanner(
            message:
                'Upcoming EMIs, subscriptions and pending payments are not deducted until you record them as paid.',
          ),
        ],
      ),
    );
  }
}
