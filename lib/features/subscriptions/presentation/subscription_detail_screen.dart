import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../core/time/frequency.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/transaction_row.dart';
import '../application/subscription_actions.dart';
import '../domain/subscription.dart';
import 'subscription_ui.dart';

enum _Menu { edit, skip, pause, resume, cancel, delete }

class SubscriptionDetailScreen extends ConsumerStatefulWidget {
  const SubscriptionDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<SubscriptionDetailScreen> createState() => _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState extends ConsumerState<SubscriptionDetailScreen> {
  final _key = newIdempotencyKey();

  Future<void> _setStatus(Subscription s, SubscriptionStatus status) => runAction(
        context,
        ref,
        action: const SetSubscriptionStatusAction(),
        input: SubscriptionStatusInput(id: s.id, status: status),
        idempotencyKey: '$_key-status-${s.version}-${status.name}',
      );

  Future<void> _skip(Subscription s) async {
    final ok = await showFinnConfirm(
      context,
      title: 'Skip this renewal?',
      message: 'Moves the next due date from ${DateFormats.dayMonthYear.format(s.nextDueDate)} to '
          '${DateFormats.dayMonthYear.format(SubscriptionSchedule.nextCycleAfterCurrent(s))} '
          'without recording a payment — for a free month or a waived charge. Your balance stays the same.',
      confirmLabel: 'Skip renewal',
    );
    if (!ok || !mounted) return;
    await runAction(
      context,
      ref,
      action: const SkipSubscriptionCycleAction(),
      input: SkipSubscriptionCycleInput(subscriptionId: s.id, cycleDate: s.nextDueDate),
      idempotencyKey: 'sub-skip-${s.id}-${DateFormats.iso.format(s.nextDueDate)}',
    );
  }

  Future<void> _menu(Subscription s) async {
    final choice = await showFinnActionMenu<_Menu>(
      context,
      title: s.name,
      items: [
        const FinnMenuItem(value: _Menu.edit, label: 'Edit details', icon: LucideIcons.pencil),
        if (s.isActive) const FinnMenuItem(value: _Menu.skip, label: 'Skip this renewal', icon: LucideIcons.skipForward),
        if (s.isActive) const FinnMenuItem(value: _Menu.pause, label: 'Pause', icon: LucideIcons.pause),
        if (!s.isActive)
          FinnMenuItem(
            value: _Menu.resume,
            label: s.status == SubscriptionStatus.paused ? 'Resume' : 'Reactivate',
            icon: LucideIcons.play,
          ),
        if (s.status != SubscriptionStatus.cancelled)
          const FinnMenuItem(value: _Menu.cancel, label: 'Mark as cancelled', icon: LucideIcons.circleX),
        const FinnMenuItem(value: _Menu.delete, label: 'Delete', icon: LucideIcons.trash2, destructive: true),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _Menu.edit:
        context.push(AppRoutes.editSubscription(s.id));
      case _Menu.skip:
        await _skip(s);
      case _Menu.pause:
        await _setStatus(s, SubscriptionStatus.paused);
      case _Menu.resume:
        await _setStatus(s, SubscriptionStatus.active);
      case _Menu.cancel:
        await _setStatus(s, SubscriptionStatus.cancelled);
      case _Menu.delete:
        final done = await runAction(context, ref,
            action: const DeleteSubscriptionAction(), input: SubscriptionIdInput(id: s.id), idempotencyKey: '$_key-del');
        if (done != null && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(subscriptionDetailProvider(widget.id));
    final d = value.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.subscription.name ?? 'Subscription'),
        actions: [
          if (d != null)
            FinnIconButton(
              icon: LucideIcons.ellipsisVertical,
              tooltip: 'More actions',
              onPressed: () => _menu(d.subscription),
            ),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: AsyncView<SubscriptionDetail?>(
        value: value,
        loading: const SkeletonPulse(
          child: Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: Column(children: [CardSkeleton(height: 200), SizedBox(height: Space.x4), CardSkeleton(height: 220)]),
          ),
        ),
        builder: (context, d) {
          if (d == null) {
            return Center(
              child: EmptyState(
                icon: LucideIcons.searchX,
                title: 'This subscription no longer exists',
                message: 'It may have been deleted.',
                actionLabel: 'Back to subscriptions',
                onAction: () => context.go(AppRoutes.subscriptions),
              ),
            );
          }
          return _Body(
            detail: d,
            onMarkPaid: () => markSubscriptionPaid(context, ref, d.subscription),
            onSkip: () => _skip(d.subscription),
            onResume: () => _setStatus(d.subscription, SubscriptionStatus.active),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail, required this.onMarkPaid, required this.onSkip, required this.onResume});

  final SubscriptionDetail detail;
  final VoidCallback onMarkPaid;
  final VoidCallback onSkip;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final d = detail;
    final s = d.subscription;
    final sections = <Widget>[
      _Hero(detail: d),
      const SizedBox(height: Space.x4),
      if (s.isActive)
        _NextRenewal(detail: d, onMarkPaid: onMarkPaid, onSkip: onSkip)
      else
        InfoBanner(
          icon: s.status == SubscriptionStatus.paused ? LucideIcons.pause : LucideIcons.circleX,
          message: s.status == SubscriptionStatus.paused
              ? 'Paused: no renewals are expected and it does not count towards your monthly commitment.'
              : 'Cancelled: no renewals are expected. Past payments stay in your transactions.',
          actionLabel: s.status == SubscriptionStatus.paused ? 'Resume' : 'Reactivate',
          onAction: onResume,
        ),
      const SizedBox(height: Space.section),
      SectionHeader(icon: LucideIcons.fileText, title: 'Details', tileColor: c.accentSubscriptions),
      const SizedBox(height: Space.x2),
      FinnCard(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x1),
        child: Column(
          children: [
            KeyValueRow(label: 'Amount', valueWidget: AmountText(s.amount, style: t.bodyStrong)),
            KeyValueRow(label: 'Billing', value: s.frequency.label),
            if (s.frequency != Frequency.monthly)
              KeyValueRow(label: 'Per month', valueWidget: AmountText(s.monthlyEquivalent, style: t.bodyStrong)),
            KeyValueRow(label: 'Per year', valueWidget: AmountText(s.annualized, style: t.bodyStrong)),
            KeyValueRow(label: 'Category', value: d.category?.name ?? 'Uncategorised'),
            KeyValueRow(label: 'Usually paid by', value: s.paymentMethod?.label ?? 'Not set'),
            KeyValueRow(label: 'Renews automatically', value: s.autoRenews ? 'Yes' : 'No'),
            if (s.startDate != null) KeyValueRow(label: 'Started', value: DateFormats.dayMonthYear.format(s.startDate!)),
            KeyValueRow(label: 'Status', valueWidget: SubscriptionDueChip(subscription: s, today: d.today)),
            if (s.note != null && s.note!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x2_5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NOTES', style: t.eyebrow),
                    const SizedBox(height: Space.x1),
                    SizedBox(width: double.infinity, child: Text(s.note!, style: t.body)),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: Space.section),
      SectionHeader(
        icon: LucideIcons.history,
        title: 'Payment history',
        subtitle: d.payments.isEmpty
            ? null
            : '${d.payments.length} recorded${AmountVisibility.hiddenOf(context) ? '' : ' · ${MoneyFormatter.format(d.paidTotal)}'}',
        tileColor: c.positive,
      ),
      const SizedBox(height: Space.x2),
      if (d.payments.isEmpty)
        FinnCard(
          variant: FinnCardVariant.muted,
          child: Text(
            'No payments recorded yet. When a renewal is charged, mark it as paid to record the expense once.',
            style: t.caption,
          ),
        )
      else
        FinnCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1),
          child: Column(
            children: [
              for (var i = 0; i < d.payments.length; i++) ...[
                if (i > 0) const FinnDivider(),
                TransactionRow(
                  key: ValueKey(d.payments[i].id),
                  transaction: d.payments[i],
                  showDate: true,
                  onTap: () => context.push(AppRoutes.transaction(d.payments[i].id)),
                ),
              ],
            ],
          ),
        ),
    ];
    return ListView(
      key: PageStorageKey('subscription-${s.id}'),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.detail});

  final SubscriptionDetail detail;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final d = detail;
    final s = d.subscription;
    final white70 = Colors.white.withValues(alpha: 0.75);
    return GradientHeroCard(
      watermark: LucideIcons.repeat,
      semanticLabel: '${s.name}, ${MoneyFormatter.spoken(s.amount)} ${s.frequency.label.toLowerCase()}, ${s.status.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SubscriptionAvatar(categoryId: s.categoryId, size: 36),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong.copyWith(color: Colors.white)),
                    Text(d.category?.name ?? 'Uncategorised', style: t.caption.copyWith(color: white70)),
                  ],
                ),
              ),
              StatusPill(
                label: s.status.label,
                color: Colors.white,
                icon: switch (s.status) {
                  SubscriptionStatus.active => LucideIcons.repeat,
                  SubscriptionStatus.paused => LucideIcons.pause,
                  SubscriptionStatus.cancelled => LucideIcons.circleX,
                },
              ),
            ],
          ),
          const SizedBox(height: Space.x4),
          AnimatedAmount(s.amount, style: t.amountHero.copyWith(color: Colors.white), fit: true),
          Text('per ${s.frequency.unit}', style: t.caption.copyWith(color: white70)),
          const SizedBox(height: Space.x4),
          Row(
            children: [
              Expanded(
                child: _HeroFigure(
                  label: 'Per month',
                  value: AmountText(s.monthlyEquivalent, style: t.amountSmall.copyWith(color: Colors.white)),
                ),
              ),
              Expanded(
                child: _HeroFigure(
                  label: 'Per year',
                  value: AmountText(s.annualized, style: t.amountSmall.copyWith(color: Colors.white)),
                ),
              ),
              Expanded(
                child: _HeroFigure(
                  label: 'Paid so far',
                  value: AmountText(d.paidTotal, style: t.amountSmall.copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: context.text.eyebrow.copyWith(color: Colors.white.withValues(alpha: 0.7))),
            const SizedBox(height: 2),
            value,
          ],
        ),
      );
}

class _NextRenewal extends StatelessWidget {
  const _NextRenewal({required this.detail, required this.onMarkPaid, required this.onSkip});

  final SubscriptionDetail detail;
  final VoidCallback onMarkPaid;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final d = detail;
    final s = d.subscription;
    final due = subscriptionDueLabel(context, s, d.today);
    final later = d.expected.where((x) => !x.isAtSameMomentAs(s.nextDueDate)).toList();
    return FinnCard(
      variant: FinnCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: LucideIcons.calendarClock, background: c.infoSoft, foreground: c.info, size: 36, iconSize: 18),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next renewal', style: t.bodyStrong),
                    Text(
                      '${DateFormats.dayMonthYear.format(s.nextDueDate)} · ${DateFormats.dueIn(s.nextDueDate, d.today)}',
                      style: t.caption,
                    ),
                  ],
                ),
              ),
              AmountText(s.amount, style: t.amountMedium),
            ],
          ),
          const SizedBox(height: Space.x3),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(label: due.label, color: due.color, icon: due.icon),
              Text('Expected · not paid yet', style: t.micro),
            ],
          ),
          const SizedBox(height: Space.x4),
          Row(
            children: [
              Expanded(
                child: FinnButton(
                  label: 'Mark paid',
                  icon: LucideIcons.circleCheck,
                  variant: d.dueState == DueState.overdue || d.dueState == DueState.dueToday
                      ? FinnButtonVariant.attention
                      : FinnButtonVariant.primary,
                  expand: true,
                  onPressed: onMarkPaid,
                ),
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                child: FinnButton(
                  label: 'Skip',
                  icon: LucideIcons.skipForward,
                  variant: FinnButtonVariant.outline,
                  expand: true,
                  onPressed: onSkip,
                ),
              ),
            ],
          ),
          if (later.isNotEmpty) ...[
            const SizedBox(height: Space.x4),
            Text('THEN EXPECTED', style: t.eyebrow),
            const SizedBox(height: Space.x1),
            Text(later.map(DateFormats.dayMonthYear.format).join('  ·  '), style: t.caption),
          ],
          const SizedBox(height: Space.x3),
          Text(
            'Marking as paid records one expense and moves the due date forward. Nothing is deducted automatically.',
            style: t.micro,
          ),
        ],
      ),
    );
  }
}
