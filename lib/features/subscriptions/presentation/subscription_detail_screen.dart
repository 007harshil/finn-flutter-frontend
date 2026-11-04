import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../core/time/frequency.dart';
import '../../../kit/kit.dart';
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
  bool _busy = false;

  /// One tap, one payment: a second tap while the first is still settling (or
  /// after the screen already moved to the next cycle) must not pay again.
  /// Leaves the screen once recorded so the user lands where they came from.
  Future<void> _markPaid(Subscription s) async {
    if (_busy) return;
    _busy = true;
    try {
      final paid = await markSubscriptionPaid(context, ref, s);
      if (paid != null && mounted && context.canPop()) context.pop();
    } finally {
      _busy = false;
    }
  }

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
    if (_busy) return;
    _busy = true;
    try {
      final done = await runAction(
        context,
        ref,
        action: const SkipSubscriptionCycleAction(),
        input: SkipSubscriptionCycleInput(subscriptionId: s.id, cycleDate: s.nextDueDate),
        idempotencyKey: 'sub-skip-${s.id}-${DateFormats.iso.format(s.nextDueDate)}',
      );
      if (done != null && mounted && context.canPop()) context.pop();
    } finally {
      _busy = false;
    }
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
    return LedgerPage(
      appBar: LedgerAppBar(
        title: d?.subscription.name ?? 'Subscription',
        actions: [
          if (d != null)
            LedgerIconButton(
              icon: LucideIcons.ellipsisVertical,
              tooltip: 'More actions',
              onPressed: () => _menu(d.subscription),
            ),
        ],
      ),
      storageKey: 'subscription-${widget.id}',
      slivers: [
        SliverToBoxAdapter(
          child: AsyncView<SubscriptionDetail?>(
            value: value,
            loading: const LedgerPageSkeleton(rows: 3),
            builder: (context, d) => d == null
                ? PageColumn(
                    top: Sp.xxl,
                    child: LedgerEmpty(
                      title: 'Subscription not found',
                      actionLabel: 'Back to subscriptions',
                      onAction: () => context.go(AppRoutes.subscriptions),
                    ),
                  )
                : _Body(
                    detail: d,
                    onMarkPaid: () => _markPaid(d.subscription),
                    onSkip: () => _skip(d.subscription),
                    onResume: () => _setStatus(d.subscription, SubscriptionStatus.active),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail, required this.onMarkPaid, required this.onSkip, required this.onResume});

  final SubscriptionDetail detail;
  final VoidCallback onMarkPaid;
  final VoidCallback onSkip;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final d = detail;
    final s = d.subscription;
    final later = d.expected.where((x) => !x.isAtSameMomentAs(s.nextDueDate)).toList();
    final note = s.note?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageColumn(
          top: Sp.lg,
          child: _Hero(detail: d, onMarkPaid: onMarkPaid, onSkip: onSkip, onResume: onResume),
        ),
        PageColumn(
          top: Sp.lg,
          child: FactTags(
            tags: [
              d.category?.name ?? 'Uncategorised',
              s.accountId == null
                  ? 'No account'
                  : (ref.watch(financeSnapshotProvider).value?.account(s.accountId!)?.name ?? 'Unknown account'),
              s.autoRenews ? 'Auto-renews' : 'Manual renewal',
              if (s.startDate != null) 'Since ${DateFormats.dayMonthYear.format(s.startDate!)}',
            ],
            highlight: {if (s.autoRenews) 'Auto-renews'},
          ),
        ),
        if (s.isActive && later.isNotEmpty)
          PageColumn(
            top: Sp.section,
            child: LedgerSection(title: 'Coming renewals', child: _DateStrip(dates: later)),
          ),
        if (note.isNotEmpty)
          PageColumn(top: Sp.md, child: LedgerNote(icon: LucideIcons.stickyNote, text: note)),
        PageColumn(
          top: Sp.section,
          child: LedgerSection(
            title: 'Payment history',
            count: d.payments.isEmpty ? null : d.payments.length,
            trailing: d.payments.isEmpty ? null : AmountText(d.paidTotal, style: t.figureSmall),
            child: d.payments.isEmpty
                ? const LedgerEmpty(icon: LucideIcons.receipt, title: 'No payments yet')
                : LedgerPanel(
                    khata: true,
                    dividerIndent: Sp.lg + 40 + Sp.md + 2,
                    children: [
                      for (final p in d.payments)
                        TransactionRow(
                          key: ValueKey(p.id),
                          transaction: p,
                          showDate: true,
                          onTap: () => context.push(AppRoutes.transaction(p.id)),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Upcoming renewal dates as small khata date blocks.
class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.dates});

  final List<DateTime> dates;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Wrap(
      spacing: Sp.sm,
      runSpacing: Sp.sm,
      children: [
        for (final d in dates.take(8))
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: Sp.sm),
            decoration: BoxDecoration(
              color: c.khata,
              borderRadius: Rad.rMd,
              border: Border.all(color: c.khataRule),
            ),
            child: Column(
              children: [
                Text('${d.day}', style: t.figureL.copyWith(fontSize: 24, height: 1)),
                const SizedBox(height: 2),
                Text(DateFormats.shortMonth.format(d), style: t.small),
              ],
            ),
          ),
      ],
    );
  }
}

/// Amount and cycle as the one number on the slab, the next charge and
/// the yearly cost under it, then the action: mark paid (or resume).
class _Hero extends StatelessWidget {
  const _Hero({required this.detail, required this.onMarkPaid, required this.onSkip, required this.onResume});

  final SubscriptionDetail detail;
  final VoidCallback onMarkPaid;
  final VoidCallback onSkip;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final s = d.subscription;
    final next = subscriptionNextCharge(context, s, d.today);
    final paused = s.status == SubscriptionStatus.paused;
    final cycleDays = s.frequency.months == 0 ? 7 : s.frequency.months * 30;
    final daysLeft = daysBetween(d.today, s.nextDueDate);
    final cycle = (1 - daysLeft / cycleDays).clamp(0.0, 1.0);
    final soon = next.color != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: '${s.name}, ${MoneyFormatter.spoken(s.amount)} ${s.frequency.label.toLowerCase()}, ${s.status.label}',
          child: BahiSlab(
            leading: LucideIcons.repeat,
            label: d.category?.name ?? 'Uncategorised',
            figure: SlabFigure(s.amount),
            caption: 'per ${s.frequency.unit}',
            stamp: SlabStamp(
              label: s.status.label,
              tone: paused ? SlabTone.warn : (s.isActive ? SlabTone.good : SlabTone.neutral),
            ),
            // How far through the current billing cycle we are.
            visual: SlabRing(
              value: s.isActive ? cycle : 0,
              size: 96,
              color: soon ? Slab.bad : Slab.cool,
              top: s.isActive ? '${daysLeft < 0 ? 0 : daysLeft}' : '—',
              bottom: daysLeft == 1 ? 'day left' : 'days left',
            ),
            stats: [
              if (s.isActive)
                SlabStat(
                  label: 'Next renewal',
                  value: Text(
                    DateFormats.dayMonthYear.format(s.nextDueDate),
                    style: context.type.figure.copyWith(color: soon ? Slab.bad : Slab.ink),
                  ),
                ),
              if (s.frequency != Frequency.monthly) SlabStat.money(label: 'Per month', amount: s.monthlyEquivalent),
              SlabStat.money(label: 'Per year', amount: s.annualized, color: Slab.warn),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),
        if (s.isActive)
          Row(
            children: [
              Expanded(
                child: LedgerButton(
                  label: 'Mark paid',
                  icon: LucideIcons.circleCheck,
                  expand: true,
                  onPressed: onMarkPaid,
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: LedgerButton(
                  label: 'Skip',
                  icon: LucideIcons.skipForward,
                  variant: LedgerButtonVariant.secondary,
                  expand: true,
                  onPressed: onSkip,
                ),
              ),
            ],
          )
        else
          LedgerButton(
            label: paused ? 'Resume' : 'Reactivate',
            icon: LucideIcons.play,
            expand: true,
            onPressed: onResume,
          ),
      ],
    );
  }
}
