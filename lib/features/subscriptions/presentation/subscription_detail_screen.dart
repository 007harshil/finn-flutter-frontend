import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
                      message: 'It may have been deleted.',
                      actionLabel: 'Back to subscriptions',
                      onAction: () => context.go(AppRoutes.subscriptions),
                    ),
                  )
                : _Body(
                    detail: d,
                    onMarkPaid: () => markSubscriptionPaid(context, ref, d.subscription),
                    onSkip: () => _skip(d.subscription),
                    onResume: () => _setStatus(d.subscription, SubscriptionStatus.active),
                  ),
          ),
        ),
      ],
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
    final t = context.type;
    final d = detail;
    final s = d.subscription;
    final later = d.expected.where((x) => !x.isAtSameMomentAs(s.nextDueDate)).toList();
    final note = s.note?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageColumn(
          top: Sp.xl,
          child: _Hero(detail: d, onMarkPaid: onMarkPaid, onSkip: onSkip, onResume: onResume),
        ),
        PageColumn(
          top: Sp.section,
          child: LedgerSection(
            title: 'Details',
            child: LedgerPanel(
              dividerIndent: Sp.lg,
              children: [
                if (s.frequency != Frequency.monthly)
                  LedgerFact(label: 'Per month', value: AmountText(s.monthlyEquivalent, style: t.figure)),
                LedgerFact(label: 'Per year', value: AmountText(s.annualized, style: t.figure)),
                LedgerFact(label: 'Category', text: d.category?.name ?? 'Uncategorised'),
                LedgerFact(label: 'Usually paid by', text: s.paymentMethod?.label ?? 'Not set'),
                LedgerFact(label: 'Renews automatically', text: s.autoRenews ? 'Yes' : 'No'),
                if (s.startDate != null) LedgerFact(label: 'Started', text: DateFormats.dayMonthYear.format(s.startDate!)),
                if (s.isActive && later.isNotEmpty)
                  LedgerFact(label: 'Then', text: later.map(DateFormats.dayMonthYear.format).join(', ')),
                if (note.isNotEmpty) LedgerFact(label: 'Notes', text: note, stacked: true),
              ],
            ),
          ),
        ),
        PageColumn(
          top: Sp.section,
          child: LedgerSection(
            title: 'Payment history',
            count: d.payments.isEmpty ? null : d.payments.length,
            trailing: d.payments.isEmpty ? null : AmountText(d.paidTotal, style: t.figureSmall),
            child: d.payments.isEmpty
                ? Text('No payments recorded yet.', style: t.label)
                : LedgerPanel(
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

/// Amount and cycle as the one number, the next charge beneath it, then the
/// action: mark paid (or resume when paused or cancelled).
class _Hero extends StatelessWidget {
  const _Hero({required this.detail, required this.onMarkPaid, required this.onSkip, required this.onResume});

  final SubscriptionDetail detail;
  final VoidCallback onMarkPaid;
  final VoidCallback onSkip;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final d = detail;
    final s = d.subscription;
    final next = subscriptionNextCharge(context, s, d.today);
    final paused = s.status == SubscriptionStatus.paused;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(d.category?.name ?? 'Uncategorised', style: t.label),
        const SizedBox(height: Sp.xs),
        Semantics(
          container: true,
          label:
              '${s.name}, ${MoneyFormatter.spoken(s.amount)} ${s.frequency.label.toLowerCase()}, ${s.status.label}',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(child: AnimatedAmount(s.amount, style: t.figureXL, fit: true, animateOnMount: true)),
              const SizedBox(width: Sp.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('per ${s.frequency.unit}', style: t.figureSmall),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),
        if (s.isActive) ...[
          Text('Next renewal', style: t.label),
          const SizedBox(height: 2),
          Text(
            '${DateFormats.dayMonthYear.format(s.nextDueDate)}, ${DateFormats.dueIn(s.nextDueDate, d.today)}',
            style: t.bodyStrong.copyWith(color: next.color),
          ),
          const SizedBox(height: Sp.xl),
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
          ),
          const SizedBox(height: Sp.md),
          Text(
            'Records one expense and moves the due date forward. Nothing is deducted automatically.',
            style: t.label.copyWith(color: c.inkFaint),
          ),
        ] else ...[
          LedgerNote(
            icon: paused ? LucideIcons.pause : LucideIcons.circleX,
            text: paused
                ? 'Paused. No renewals are expected and it does not count towards your monthly cost.'
                : 'Cancelled. No renewals are expected. Past payments stay in your transactions.',
          ),
          const SizedBox(height: Sp.lg),
          LedgerButton(
            label: paused ? 'Resume' : 'Reactivate',
            icon: LucideIcons.play,
            expand: true,
            onPressed: onResume,
          ),
        ],
      ],
    );
  }
}
