import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../core/time/frequency.dart';
import '../../../design_system/design_system.dart'
    show AmountText, AnimatedAmount, BottomClearanceX, FinnMenuItem, showFinnActionMenu, showFinnConfirm;
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../application/subscription_actions.dart';
import '../domain/subscription.dart';
import 'subscription_ui.dart';

enum _Menu { edit, skip, pause, resume, cancel, delete }

/// One subscription: what it costs, when it renews and the two things to
/// do about it (mark paid, skip), then its details and payments.
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
      message:
          'Moves the next renewal from ${DateFormats.dayMonth.format(s.nextDueDate)} to '
          '${DateFormats.dayMonth.format(SubscriptionSchedule.nextCycleAfterCurrent(s))} without recording a payment.',
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
        final done = await runAction(
          context,
          ref,
          action: const DeleteSubscriptionAction(),
          input: SubscriptionIdInput(id: s.id),
          idempotencyKey: '$_key-del',
        );
        if (done != null && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(subscriptionDetailProvider(widget.id));
    final d = value.value;
    return UiPage(
      title: d?.subscription.name ?? 'Subscription',
      actions: [
        if (d != null)
          UiIconButton(icon: LucideIcons.ellipsis, tooltip: 'More actions', onPressed: () => _menu(d.subscription)),
      ],
      body: AsyncView<SubscriptionDetail?>(
        value: value,
        loading: const _Placeholder(),
        builder: (context, d) {
          if (d == null) {
            return Center(
              child: UiEmpty(
                icon: LucideIcons.searchX,
                title: 'This subscription no longer exists',
                action: 'Back to subscriptions',
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
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final d = detail;
    final s = d.subscription;
    final due = subscriptionDue(c, s, d.today);
    final paused = s.status == SubscriptionStatus.paused;
    final note = s.note?.trim() ?? '';
    Widget money(Money m) => AmountText(m, style: t.body);
    return ListView(
      key: PageStorageKey('subscription-${s.id}'),
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.sm, UiSpace.gutter, context.bottomClearance),
      children: [
        UiColumnWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiReveal(
                index: 0,
                child: UiHero(
                  label: '${d.category?.name ?? 'Uncategorised'} · ${s.frequency.label}',
                  value: AnimatedAmount(s.amount, style: t.amount, fit: true, animateOnMount: true),
                  caption: s.isActive
                      ? 'Renews ${DateFormats.dayMonth.format(s.nextDueDate)} · ${due.label}'
                      : (paused ? 'Paused · not in your monthly total' : 'Cancelled · no renewals expected'),
                  captionColor: due.color,
                ),
              ),
              const SizedBox(height: UiSpace.xl),
              if (s.isActive)
                Row(
                  children: [
                    Expanded(child: UiPrimaryButton(label: 'Mark paid', onPressed: onMarkPaid)),
                    const SizedBox(width: UiSpace.md),
                    Expanded(child: UiSecondaryButton(label: 'Skip', icon: LucideIcons.skipForward, onPressed: onSkip)),
                  ],
                )
              else
                UiPrimaryButton(label: paused ? 'Resume' : 'Reactivate', onPressed: onResume),
              UiSection(
                title: 'Details',
                child: UiPanelList(
                  children: [
                    if (s.frequency != Frequency.monthly)
                      UiDetailRow(label: 'Per month', valueWidget: money(s.monthlyEquivalent)),
                    UiDetailRow(label: 'Per year', valueWidget: money(s.annualized)),
                    UiDetailRow(label: 'Paid by', value: s.paymentMethod?.label ?? 'Not set'),
                    UiDetailRow(label: 'Renews automatically', value: s.autoRenews ? 'Yes' : 'No'),
                    if (s.startDate != null)
                      UiDetailRow(label: 'Started', value: DateFormats.dayMonthYear.format(s.startDate!)),
                    if (note.isNotEmpty) UiNoteRow(label: 'Note', text: note),
                  ],
                ),
              ),
              _Payments(detail: d),
            ],
          ),
        ),
      ],
    );
  }
}

class _Payments extends StatelessWidget {
  const _Payments({required this.detail});

  final SubscriptionDetail detail;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final d = detail;
    return UiSection(
      title: 'Payments',
      trailing: d.payments.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: UiSpace.sm),
              child: AmountText(d.paidTotal, style: t.label),
            ),
      child: d.payments.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(left: UiSpace.xs),
              child: Text('None recorded yet', style: t.label),
            )
          : UiPanelList(
              children: [
                for (final p in d.payments)
                  UiListRow(
                    key: ValueKey(p.id),
                    title: DateFormats.dayMonthYear.format(p.date),
                    subtitle: p.paymentMethod?.label,
                    trailing: AmountText(p.amount, style: t.figureSmall),
                    onTap: () => context.push(AppRoutes.transaction(p.id)),
                  ),
              ],
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.lg, UiSpace.gutter, 0),
      child: UiColumnWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UiPlaceholder(width: 140, height: 12),
            SizedBox(height: UiSpace.md),
            UiPlaceholder(width: 160, height: 40),
            SizedBox(height: UiSpace.xl + UiSpace.lg),
            UiPlaceholder(height: 52, radius: UiRadius.control),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 200, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
