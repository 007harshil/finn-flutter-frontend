import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../../finance/ledger.dart';
import '../../../../shared/presentation/async_view.dart';
import '../../../../ui/ui.dart';

/// The one number that matters: what is free to spend. Below it, a thin bar
/// of all cash with the set-aside part beside the free part, and the two
/// totals. Tapping the totals swaps "set aside" for its goals / emergency
/// split; the info button explains the maths.
class HeroBalanceCard extends ConsumerWidget {
  const HeroBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<BalanceSnapshot>(
      value: ref.watch(balanceProvider),
      loading: const _HeroPlaceholder(),
      builder: (context, b) => _Hero(balance: b),
    );
  }
}

class _Hero extends StatefulWidget {
  const _Hero({required this.balance});

  final BalanceSnapshot balance;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  bool _split = false;

  void _openBreakdown() => showFinnSheet<void>(context, builder: (_) => BalanceBreakdownSheet(balance: widget.balance));

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final b = widget.balance;
    final over = b.available.isNegative;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: UiSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Available to spend', style: t.label),
              const Spacer(),
              _InfoButton(onTap: _openBreakdown),
            ],
          ),
          Semantics(
            button: true,
            hint: 'Shows how this is calculated',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openBreakdown,
              child: AnimatedAmount(
                b.available,
                style: t.amount.copyWith(color: over ? c.negative : c.ink),
                decimals: DecimalDisplay.none,
                fit: true,
                animateOnMount: true,
              ),
            ),
          ),
          if (over) ...[
            const SizedBox(height: UiSpace.xs),
            Text('More is set aside than you have in cash', style: t.small.copyWith(color: c.negative)),
          ],
          const SizedBox(height: UiSpace.lg),
          _CashBar(shares: _Shares.of(b), split: _split),
          const SizedBox(height: UiSpace.xs),
          _Totals(
            balance: b,
            split: _split,
            onToggle: () {
              HapticFeedback.selectionClick();
              setState(() => _split = !_split);
            },
          ),
        ],
      ),
    );
  }
}

class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'How this is calculated',
      child: InkResponse(
        radius: 22,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: Icon(LucideIcons.info, size: 18, color: UiColors.of(context).inkSoft),
        ),
      ),
    );
  }
}

/// "Cash · Set aside", or "Goals · Emergency fund" once split. The whole
/// row is one toggle.
class _Totals extends StatelessWidget {
  const _Totals({required this.balance, required this.split, required this.onToggle});

  final BalanceSnapshot balance;
  final bool split;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final b = balance;
    final (left, right) = split
        ? (
            _Stat(label: 'Goals', amount: b.earmarkedGoals, dot: c.goals),
            _Stat(label: 'Emergency fund', amount: b.earmarkedEmergency, dot: c.emergency, end: true),
          )
        : (
            _Stat(label: 'Cash', amount: b.cash, dot: c.ink),
            _Stat(label: 'Set aside', amount: b.earmarked, dot: c.inkFaint, end: true),
          );
    return Semantics(
      button: true,
      toggled: split,
      hint: split ? 'Shows cash and set aside' : 'Splits set aside into goals and emergency fund',
      child: InkWell(
        onTap: onToggle,
        borderRadius: UiRadius.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: UiSpace.sm),
          child: AnimatedSwitcher(
            duration: UiMotion.of(context).normal,
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
            child: Row(
              key: ValueKey(split),
              children: [
                Expanded(child: left),
                const SizedBox(width: UiSpace.md),
                Expanded(child: right),
                const SizedBox(width: UiSpace.xs),
                ExcludeSemantics(
                  child: Icon(split ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16, color: c.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.amount, required this.dot, this.end = false});

  final String label;
  final Money amount;
  final Color dot;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label, style: t.small, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 2),
          AmountText(
            amount,
            style: t.figureSmall,
            decimals: DecimalDisplay.none,
            fit: true,
            textAlign: end ? TextAlign.end : null,
          ),
        ],
      ),
    );
  }
}

/// Shares of all cash, each 0..1. When more is set aside than there is
/// cash, the set-aside parts fill the bar.
@immutable
class _Shares {
  const _Shares(this.free, this.goals, this.emergency);

  factory _Shares.of(BalanceSnapshot b) {
    final over = b.available.isNegative;
    final base = over ? b.earmarked.paise : b.cash.paise;
    if (base <= 0) return const _Shares(0, 0, 0);
    double share(int paise) => (paise / base).clamp(0.0, 1.0);
    return _Shares(
      over ? 0 : share(b.available.paise),
      share(b.earmarkedGoals.paise),
      share(b.earmarkedEmergency.paise),
    );
  }

  final double free;
  final double goals;
  final double emergency;

  _Shares lerpTo(_Shares o, double t) =>
      _Shares(free + (o.free - free) * t, goals + (o.goals - goals) * t, emergency + (o.emergency - emergency) * t);

  @override
  bool operator ==(Object other) =>
      other is _Shares && other.free == free && other.goals == goals && other.emergency == emergency;

  @override
  int get hashCode => Object.hash(free, goals, emergency);
}

class _SharesTween extends Tween<_Shares> {
  _SharesTween(_Shares end) : super(begin: const _Shares(0, 0, 0), end: end);

  @override
  _Shares lerp(double t) => begin!.lerpTo(end!, t);
}

/// Whole width = cash. Ink = free to spend; the rest = set aside, neutral
/// until split, then coloured by purpose.
class _CashBar extends StatelessWidget {
  const _CashBar({required this.shares, required this.split});

  final _Shares shares;
  final bool split;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final m = UiMotion.of(context);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<_Shares>(
        tween: _SharesTween(shares),
        duration: m.settle,
        curve: UiMotion.ease,
        builder: (context, s, _) => TweenAnimationBuilder<double>(
          tween: Tween(end: split ? 1 : 0),
          duration: m.normal,
          curve: Curves.easeOutCubic,
          builder: (context, k, _) => CustomPaint(
            size: const Size.fromHeight(6),
            painter: _BarPainter(
              shares: s,
              split: k,
              track: c.muted,
              free: c.ink,
              aside: c.inkFaint.withValues(alpha: 0.55),
              goals: c.goals,
              emergency: c.emergency,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.shares,
    required this.split,
    required this.track,
    required this.free,
    required this.aside,
    required this.goals,
    required this.emergency,
  });

  final _Shares shares;
  final double split;
  final Color track;
  final Color free;
  final Color aside;
  final Color goals;
  final Color emergency;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final whole = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(whole, Paint()..color = track);
    canvas.save();
    canvas.clipRRect(whole);
    const gap = 2.0;
    var x = 0.0;
    for (final (share, color) in [
      (shares.free, free),
      (shares.goals, Color.lerp(aside, goals, split)!),
      (shares.emergency, Color.lerp(aside, emergency, split)!),
    ]) {
      final w = share * size.width;
      if (w <= 0.5) continue;
      canvas.drawRect(Rect.fromLTWH(x, 0, w - (x + w < size.width ? gap : 0), size.height), Paint()..color = color);
      x += w;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.shares != shares ||
      o.split != split ||
      o.track != track ||
      o.free != free ||
      o.aside != aside ||
      o.goals != goals ||
      o.emergency != emergency;
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: UiSpace.xs, vertical: UiSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UiPlaceholder(width: 120, height: 12),
          SizedBox(height: UiSpace.md),
          UiPlaceholder(width: 200, height: 40),
          SizedBox(height: 20),
          UiPlaceholder(height: 6),
          SizedBox(height: UiSpace.lg),
          UiPlaceholder(height: 36),
        ],
      ),
    );
  }
}

/// Explains how "available to spend" is derived from the ledger.
class BalanceBreakdownSheet extends StatelessWidget {
  const BalanceBreakdownSheet({super.key, required this.balance});

  final BalanceSnapshot balance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    Widget line(String label, Money amount, {SignDisplay sign = SignDisplay.auto, bool strong = false, Color? color}) {
      return KeyValueRow(
        label: label,
        valueWidget: AmountText(amount, sign: sign, color: color, style: strong ? t.amountMedium : t.amountSmall),
      );
    }

    return FinnSheetScaffold(
      title: 'How your balance adds up',
      description: 'Set-aside money is still yours. It is simply earmarked so you do not spend it by accident.',
      footer: FinnButton(label: 'Got it', expand: true, onPressed: () => Navigator.of(context).maybePop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line('Opening balance', balance.openingBalance),
          line('Money in', balance.totalInflow, sign: SignDisplay.always, color: c.positive),
          line('Money out', -balance.totalOutflow, sign: SignDisplay.always),
          const FinnDivider(),
          line('Cash · bank & wallet', balance.cash, strong: true),
          line('Set aside for goals', -balance.earmarkedGoals, sign: SignDisplay.always),
          line('Set aside for emergencies', -balance.earmarkedEmergency, sign: SignDisplay.always),
          const FinnDivider(),
          line('Available to spend', balance.available, strong: true),
          const SizedBox(height: UiSpace.lg),
          const InfoBanner(
            message:
                'Upcoming EMIs, subscriptions and pending payments are not deducted until you record them as paid.',
          ),
        ],
      ),
    );
  }
}
