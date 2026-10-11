import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../application/pending_actions.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

enum _Menu { edit, writeOff, delete }

class PendingDetailScreen extends ConsumerStatefulWidget {
  const PendingDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<PendingDetailScreen> createState() => _PendingDetailScreenState();
}

class _PendingDetailScreenState extends ConsumerState<PendingDetailScreen> {
  final _key = newIdempotencyKey();

  Future<void> _menu(PendingView v) async {
    final hasSettlements = v.settlements.isNotEmpty;
    final choice = await showFinnActionMenu<_Menu>(
      context,
      title: v.payment.purpose,
      items: [
        const FinnMenuItem(value: _Menu.edit, label: 'Edit details', icon: LucideIcons.pencil),
        if (v.status.isActive)
          const FinnMenuItem(value: _Menu.writeOff, label: 'Write off what is left', icon: LucideIcons.ban),
        FinnMenuItem(
          value: _Menu.delete,
          label: hasSettlements ? 'Delete — unavailable, settlements exist' : 'Delete',
          icon: LucideIcons.trash2,
          destructive: true,
          enabled: !hasSettlements,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _Menu.edit:
        context.push(AppRoutes.editPending(v.payment.id));
      case _Menu.writeOff:
        await runAction(context, ref,
            action: const CancelPendingAction(), input: PendingIdInput(id: v.payment.id), idempotencyKey: '$_key-off');
      case _Menu.delete:
        final done = await runAction(context, ref,
            action: const DeletePendingAction(), input: PendingIdInput(id: v.payment.id), idempotencyKey: '$_key-del');
        if (done != null && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(pendingViewProvider(widget.id));
    final v = value.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(v?.payment.counterparty ?? 'Money owed'),
        actions: [
          if (v != null)
            FinnIconButton(icon: LucideIcons.ellipsisVertical, tooltip: 'More actions', onPressed: () => _menu(v)),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: AsyncView<PendingView?>(
        value: value,
        loading: const SkeletonPulse(
          child: Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: Column(children: [CardSkeleton(height: 200), SizedBox(height: Space.x4), CardSkeleton(height: 220)]),
          ),
        ),
        builder: (context, v) {
          if (v == null) {
            return Center(
              child: EmptyState(
                icon: LucideIcons.searchX,
                title: 'This item no longer exists',
                message: 'It may have been deleted.',
                actionLabel: 'Back to money owed',
                onAction: () => context.go(AppRoutes.pending),
              ),
            );
          }
          return _Body(view: v, onSettle: () => context.push(AppRoutes.settlePending(v.payment.id)));
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view, required this.onSettle});

  final PendingView view;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final v = view;
    final p = v.payment;
    final sections = <Widget>[
      _Hero(view: v),
      if (v.status.isActive) ...[
        const SizedBox(height: Space.x3),
        FinnButton(
          label: p.direction.isOwe ? 'Settle · I paid ${p.counterparty}' : 'Settle · ${p.counterparty} paid me',
          icon: LucideIcons.circleCheck,
          expand: true,
          size: FinnButtonSize.lg,
          onPressed: onSettle,
        ),
      ],
      if (v.isLongPending) ...[
        const SizedBox(height: Space.x4),
        _LongPendingNote(view: v),
      ],
      const SizedBox(height: Space.x4),
      const InfoBanner(
        icon: LucideIcons.info,
        message: 'Creating this did not change your balance. Settling records the cash movement once.',
      ),
      const SizedBox(height: Space.section),
      SectionHeader(icon: LucideIcons.fileText, title: 'Details', tileColor: c.accentPending),
      const SizedBox(height: Space.x2),
      FinnCard(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x1),
        child: Column(
          children: [
            KeyValueRow(label: 'Purpose', value: p.purpose),
            KeyValueRow(label: 'Reason', value: p.kind.label),
            KeyValueRow(label: 'Status', valueWidget: _StatusValue(view: v)),
            KeyValueRow(label: 'Created', value: DateFormats.dayMonthYear.format(p.createdDate)),
            KeyValueRow(
              label: 'Due',
              value: p.dueDate == null
                  ? 'No due date'
                  : '${DateFormats.dayMonthYear.format(p.dueDate!)}${v.status.isActive ? ' · ${DateFormats.dueIn(p.dueDate!, v.today)}' : ''}',
              valueColor: v.isOverdue ? c.negative : null,
            ),
            if (p.notes != null && p.notes!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x2_5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NOTES', style: t.eyebrow),
                    const SizedBox(height: Space.x1),
                    SizedBox(width: double.infinity, child: Text(p.notes!, style: t.body)),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: Space.section),
      SectionHeader(
        icon: LucideIcons.history,
        title: 'Settlements',
        subtitle: v.settlements.isEmpty ? null : '${v.settlements.length} recorded',
        tileColor: c.positive,
      ),
      const SizedBox(height: Space.x2),
      if (v.settlements.isEmpty)
        FinnCard(
          variant: FinnCardVariant.muted,
          child: Text(
            v.status.isActive
                ? 'Nothing settled yet. Record a full or partial settlement when money changes hands.'
                : 'No settlements were recorded.',
            style: t.caption,
          ),
        )
      else
        FinnCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x1),
          child: Column(
            children: [
              for (var i = 0; i < v.settlements.length; i++) ...[
                if (i > 0) const FinnDivider(),
                _SettlementRow(settlement: v.settlements[i], direction: p.direction),
              ],
            ],
          ),
        ),
      if (v.settlements.isNotEmpty) ...[
        const SizedBox(height: Space.x3),
        Text(
          'Items with settlements cannot be deleted, so your history stays accurate. Write off the rest instead.',
          style: t.micro,
        ),
      ],
    ];
    return ListView(
      key: PageStorageKey('pending-${p.id}'),
      padding: EdgeInsets.fromLTRB(0, Space.x2, 0, context.bottomClearance),
      children: [
        for (var i = 0; i < sections.length; i++)
          ResponsiveCenter(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: i == 0 ? StaggeredEntrance(child: sections[i]) : sections[i],
          ),
      ],
    );
  }
}

/// Soft reminder once an item has been open longer than
/// [PendingView.longPendingDays]: informative, never "late".
class _LongPendingNote extends StatelessWidget {
  const _LongPendingNote({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final who = v.payment.counterparty;
    final amount = AmountVisibility.hiddenOf(context)
        ? 'an amount'
        : AmountText.formatted(v.outstanding, decimals: DecimalDisplay.none);
    final days = '${v.daysOpen} days';
    return InfoBanner(
      tone: FinnTone.warning,
      icon: LucideIcons.hourglass,
      title: '$days have passed',
      message: v.payment.direction.isOwe
          ? 'You have $amount pending to pay $who and have not paid it yet. It has been $days.'
          : '$who still has $amount pending to pay you. It has been $days.',
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final v = view;
    final p = v.payment;
    final white70 = Colors.white.withValues(alpha: 0.75);
    return GradientHeroCard(
      watermark: LucideIcons.handshake,
      semanticLabel: '${p.direction.sentence(p.counterparty)}. Outstanding ${MoneyFormatter.spoken(v.outstanding)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PendingDirectionLabel(direction: p.direction, onGradient: true),
              const Spacer(),
              _StatusValue(view: v, onGradient: true),
            ],
          ),
          const SizedBox(height: Space.x3),
          Text(p.direction.sentence(p.counterparty), style: t.bodyStrong.copyWith(color: Colors.white)),
          const SizedBox(height: Space.x1),
          AnimatedAmount(v.outstanding, style: t.amountHero.copyWith(color: Colors.white), fit: true),
          Text(v.status == PendingStatus.cancelled ? 'Written off' : 'outstanding',
              style: t.caption.copyWith(color: white70)),
          const SizedBox(height: Space.x4),
          FinnProgressBar(
            value: v.settledBps / 10000,
            color: Colors.white,
            trackColor: Colors.white.withValues(alpha: 0.18),
            semanticsLabel: 'Settled so far',
          ),
          const SizedBox(height: Space.x3),
          Row(
            children: [
              Expanded(child: _HeroFigure(label: 'Original', amount: AmountText(p.originalAmount, style: t.amountSmall.copyWith(color: Colors.white)))),
              Expanded(child: _HeroFigure(label: 'Settled', amount: AmountText(v.settled, style: t.amountSmall.copyWith(color: Colors.white)))),
              Expanded(child: _HeroFigure(label: 'Outstanding', amount: AmountText(v.outstanding, style: t.amountSmall.copyWith(color: Colors.white)))),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.amount});

  final String label;
  final Widget amount;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: context.text.eyebrow.copyWith(color: Colors.white.withValues(alpha: 0.7))),
            const SizedBox(height: 2),
            amount,
          ],
        ),
      );
}

class _StatusValue extends StatelessWidget {
  const _StatusValue({required this.view, this.onGradient = false});

  final PendingView view;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (color, icon) = switch (view.status) {
      PendingStatus.open => (c.info, LucideIcons.circleDot),
      PendingStatus.partiallySettled => (c.warning, LucideIcons.hourglass),
      PendingStatus.settled => (c.positive, LucideIcons.circleCheck),
      PendingStatus.cancelled => (c.textSecondary, LucideIcons.ban),
    };
    if (onGradient) {
      return StatusPill(label: view.isOverdue ? 'Overdue' : view.status.label, color: Colors.white, icon: icon);
    }
    return StatusPill(label: view.status.label, color: color, icon: icon);
  }
}

class _SettlementRow extends StatelessWidget {
  const _SettlementRow({required this.settlement, required this.direction});

  final PendingSettlement settlement;
  final PendingDirection direction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final s = settlement;
    final txId = s.transactionId;
    final meta = [
      DateFormats.dayMonthYear.format(s.date),
      if (s.method != null) s.method!.label,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x2_5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                icon: LucideIcons.circleCheck,
                background: c.positiveSoft,
                foreground: c.positive,
                size: 32,
                iconSize: 16,
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(direction.isOwe ? 'You paid' : 'You received', style: t.bodyStrong),
                    Text(meta, style: t.caption),
                  ],
                ),
              ),
              AmountText(s.amount, style: t.amountSmall),
            ],
          ),
          if (s.note != null && s.note!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: Space.x1),
              child: Text(s.note!, style: t.caption),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 44, top: Space.x1),
            child: txId == null
                ? Row(children: [
                    Icon(LucideIcons.circleSlash, size: 13, color: c.textTertiary),
                    const SizedBox(width: Space.x1),
                    Flexible(child: Text('Settled outside your tracked cash', style: t.micro)),
                  ])
                : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => context.push(AppRoutes.transaction(txId)),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(Dimens.minTouch, 36),
                        foregroundColor: c.info,
                        textStyle: t.label.copyWith(fontWeight: FontWeight.w800),
                      ),
                      icon: const Icon(LucideIcons.link2, size: 14),
                      label: const Text('View linked transaction'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
