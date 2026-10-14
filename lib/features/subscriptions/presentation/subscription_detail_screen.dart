import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../core/time/frequency.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/luxe_async.dart';
import '../../transactions/domain/transaction.dart';
import '../application/subscription_actions.dart';
import '../domain/subscription.dart';
import 'subscription_ui.dart';

enum _Menu { edit, skip, pause, resume, cancel, delete }

/// One plan: the price and a countdown ring to the next renewal, the two
/// things you do with it (mark paid, skip), then details and history.
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
    final ok = await showLuxeConfirm(
      context,
      title: 'Skip this renewal?',
      message:
          'Moves the next due date from ${DateFormats.dayMonthYear.format(s.nextDueDate)} to '
          '${DateFormats.dayMonthYear.format(SubscriptionSchedule.nextCycleAfterCurrent(s))} '
          'without recording a payment — for a free month or a waived charge. Your balance stays the same.',
      confirmLabel: 'Skip renewal',
      icon: LucideIcons.skipForward,
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
    final choice = await showLuxeMenu<_Menu>(
      context,
      title: s.name,
      eyebrow: 'Subscription',
      items: [
        const LuxeMenuItem(value: _Menu.edit, label: 'Edit details', icon: LucideIcons.pencil),
        if (s.isActive)
          const LuxeMenuItem(
            value: _Menu.skip,
            label: 'Skip this renewal',
            icon: LucideIcons.skipForward,
            hint: 'Free month or waived charge',
          ),
        if (s.isActive)
          const LuxeMenuItem(
            value: _Menu.pause,
            label: 'Pause',
            icon: LucideIcons.pause,
            hint: 'Stops counting until you resume',
          ),
        if (!s.isActive)
          LuxeMenuItem(
            value: _Menu.resume,
            label: s.status == SubscriptionStatus.paused ? 'Resume' : 'Reactivate',
            icon: LucideIcons.play,
          ),
        if (s.status != SubscriptionStatus.cancelled)
          const LuxeMenuItem(value: _Menu.cancel, label: 'Mark as cancelled', icon: LucideIcons.circleX),
        const LuxeMenuItem(value: _Menu.delete, label: 'Delete', icon: LucideIcons.trash2, destructive: true),
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
        final ok = await showLuxeConfirm(
          context,
          title: 'Delete ${s.name}?',
          message: 'The plan is removed. Payments already recorded stay in your transactions.',
          confirmLabel: 'Delete',
          icon: LucideIcons.trash2,
          destructive: true,
        );
        if (!ok || !mounted) return;
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
    return LuxeDetailPage(
      title: d?.subscription.name ?? 'Subscription',
      storageKey: 'subscription-${widget.id}',
      actions: [
        if (d != null)
          LuxeIconButton(
            icon: LucideIcons.ellipsis,
            tooltip: 'More actions',
            style: LuxeIconStyle.ghost,
            size: 40,
            onPressed: () => _menu(d.subscription),
          ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: LuxeAsync<SubscriptionDetail?>(
            value: value,
            loading: const LuxePageSkeleton(hero: 230, rows: 3, controls: false),
            errorTitle: 'Could not load this subscription',
            builder: (context, d) {
              if (d == null) {
                return LuxeEmpty(
                  icon: LucideIcons.searchX,
                  title: 'This subscription no longer exists',
                  message: 'It may have been deleted.',
                  actionLabel: 'Back to subscriptions',
                  onAction: () => context.go(AppRoutes.subscriptions),
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
    final p = context.luxe;
    final t = context.lt;
    final d = detail;
    final s = d.subscription;
    var i = 0;
    Widget r(Widget child) => Reveal(index: i++, child: child);
    final paused = s.status == SubscriptionStatus.paused;
    final note = s.note?.trim() ?? '';
    final hidden = AmountVisibility.hiddenOf(context);
    return ResponsiveCenter(
      padding: const EdgeInsets.symmetric(horizontal: LuxeSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          r(
            Row(
              children: [
                SubscriptionAvatar(categoryId: s.categoryId, size: 52),
                const SizedBox(width: 16),
                Expanded(
                  child: LuxeTitle(
                    eyebrow: d.category?.name ?? 'Uncategorised',
                    title: s.name,
                    subtitle: '${s.frequency.label} · ${s.status.label}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Reveal(
            index: i++,
            scale: 0.97,
            child: _Hero(detail: d),
          ),
          const SizedBox(height: 14),
          if (s.isActive)
            r(_NextRenewal(detail: d, onMarkPaid: onMarkPaid, onSkip: onSkip))
          else
            r(
              LuxeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        LuxeIconDisc(icon: paused ? LucideIcons.pause : LucideIcons.circleX, color: p.inkSoft),
                        const SizedBox(width: 12),
                        Expanded(child: Text(paused ? 'Paused' : 'Cancelled', style: t.heading)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      paused
                          ? 'No renewals are expected and it does not count towards your monthly commitment.'
                          : 'No renewals are expected. Past payments stay in your transactions.',
                      style: t.bodySoft,
                    ),
                    const SizedBox(height: 16),
                    LuxeButton(
                      label: paused ? 'Resume' : 'Reactivate',
                      icon: LucideIcons.play,
                      expand: true,
                      onPressed: onResume,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: LuxeSpace.section),
          r(const LuxeEyebrowHeader(label: 'Details')),
          const SizedBox(height: 12),
          r(
            LuxeFacts(
              facts: [
                LuxeFact('Amount', child: _amount(context, s.amount)),
                LuxeFact('Billing', value: s.frequency.label),
                if (s.frequency != Frequency.monthly)
                  LuxeFact('Per month', child: _amount(context, s.monthlyEquivalent)),
                LuxeFact('Per year', child: _amount(context, s.annualized)),
                LuxeFact('Category', value: d.category?.name ?? 'Uncategorised'),
                LuxeFact('Usually paid by', value: s.paymentMethod?.label ?? 'Not set'),
                LuxeFact('Renews automatically', value: s.autoRenews ? 'Yes' : 'No'),
                if (s.startDate != null) LuxeFact('Started', value: DateFormats.dayMonthYear.format(s.startDate!)),
                LuxeFact(
                  'Status',
                  child: SubscriptionDueChip(subscription: s, today: d.today),
                ),
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
            ),
          ),
          const SizedBox(height: LuxeSpace.section),
          LuxeEyebrowHeader(
            label: 'Payment history',
            caption: d.payments.isEmpty
                ? null
                : '${d.payments.length} recorded${hidden ? '' : ' · ${MoneyFormatter.format(d.paidTotal)}'}',
          ),
          const SizedBox(height: 14),
          if (d.payments.isEmpty)
            Text(
              'No payments recorded yet. When a renewal is charged, mark it as paid to record the expense once.',
              style: t.bodySoft,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var k = 0; k < d.payments.length; k++)
                  LuxeRailNode(
                    key: ValueKey(d.payments[k].id),
                    color: p.positive,
                    icon: LucideIcons.check,
                    first: k == 0,
                    last: k == d.payments.length - 1,
                    child: _PaymentRow(transaction: d.payments[k]),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static Widget _amount(BuildContext context, Money money) => LuxeAmount(
    money,
    fit: false,
    style: context.lt.label.w(650).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.detail});

  final SubscriptionDetail detail;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final d = detail;
    final s = d.subscription;
    final days = daysBetween(d.today, s.nextDueDate);
    final progress = s.isActive ? subscriptionCycleProgress(s, d.today) : 0.0;
    final ringLabel = !s.isActive ? '—' : (days < 0 ? '${-days}d' : (days == 0 ? 'Today' : '$days'));
    final ringCaption = !s.isActive
        ? s.status.label.toUpperCase()
        : (days < 0 ? 'OVERDUE' : (days == 0 ? 'RENEWS' : 'DAYS LEFT'));
    return LuxeObsidian(
      semanticLabel:
          '${s.name}, ${MoneyFormatter.spoken(s.amount)} ${s.frequency.label.toLowerCase()}, ${s.status.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LuxeAmount(
                      s.amount,
                      countFromZero: true,
                      style: t.display.copyWith(fontSize: 40, color: p.onObsidian),
                    ),
                    const SizedBox(height: 2),
                    Text('per ${s.frequency.unit}', style: t.caption.c(p.onObsidianSoft)),
                  ],
                ),
              ),
              LuxeRing(
                value: progress,
                color: days < 0 ? p.negative : p.gold,
                gradient: days < 0 ? null : p.goldGradient.colors,
                track: p.onObsidian.withValues(alpha: 0.1),
                size: 86,
                stroke: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(ringLabel, style: t.figure.copyWith(fontSize: 22, color: p.onObsidian)),
                    Text(ringCaption, style: t.eyebrow.copyWith(fontSize: 8, color: p.onObsidianSoft)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(height: 1, child: ColoredBox(color: p.onObsidian.withValues(alpha: 0.1))),
          const SizedBox(height: 16),
          LuxeFigureRow(
            onDark: true,
            children: [
              LuxeFigure(
                label: 'Per month',
                onDark: true,
                child: LuxeFigureAmount(s.monthlyEquivalent, onDark: true, size: 15),
              ),
              LuxeFigure(
                label: 'Per year',
                onDark: true,
                child: LuxeFigureAmount(s.annualized, onDark: true, size: 15),
              ),
              LuxeFigure(
                label: 'Paid so far',
                onDark: true,
                child: LuxeFigureAmount(d.paidTotal, onDark: true, size: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextRenewal extends StatelessWidget {
  const _NextRenewal({required this.detail, required this.onMarkPaid, required this.onSkip});

  final SubscriptionDetail detail;
  final VoidCallback onMarkPaid;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final d = detail;
    final s = d.subscription;
    final due = subscriptionDueLabel(context, s, d.today);
    final urgent = d.dueState == DueState.overdue || d.dueState == DueState.dueToday;
    final later = d.expected.where((x) => !x.isAtSameMomentAs(s.nextDueDate)).toList();
    return LuxeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LuxeIconDisc(icon: LucideIcons.calendarClock, color: due.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next renewal', style: t.heading),
                    Text(
                      '${DateFormats.dayMonthYear.format(s.nextDueDate)} · ${DateFormats.dueIn(s.nextDueDate, d.today)}',
                      style: t.caption,
                    ),
                  ],
                ),
              ),
              LuxeAmount(s.amount, fit: false, style: t.figure.copyWith(fontSize: 22)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              LuxeStatus(label: due.label, color: due.color, icon: due.icon),
              const SizedBox(width: 10),
              Flexible(child: Text('Expected · not paid yet', style: t.micro)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: LuxeButton(
                  label: 'Mark paid',
                  icon: LucideIcons.check,
                  variant: urgent ? LuxeButtonVariant.gold : LuxeButtonVariant.ink,
                  expand: true,
                  onPressed: onMarkPaid,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: LuxeButton(
                  label: 'Skip',
                  icon: LucideIcons.skipForward,
                  variant: LuxeButtonVariant.outline,
                  expand: true,
                  onPressed: onSkip,
                ),
              ),
            ],
          ),
          if (later.isNotEmpty) ...[
            const LuxeHairline(vertical: 16),
            Text('THEN EXPECTED', style: t.eyebrow),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final x in later)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: p.canvas,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: p.line),
                    ),
                    child: Text(DateFormats.dayMonthYear.format(x), style: t.micro.w(700).c(p.inkSoft)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 13, color: p.inkMute),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Marking as paid records one expense and moves the due date forward. Nothing is deducted automatically.',
                  style: t.micro,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final tx = transaction;
    return Squish(
      onTap: () => context.push(AppRoutes.transaction(tx.id)),
      scale: 0.98,
      semanticLabel: 'Paid ${DateFormats.dayMonthYear.format(tx.date)}, ${AmountText.spokenLabel(tx.amount)}',
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(DateFormats.dayMonthYear.format(tx.date), style: t.label.w(700).c(p.ink)),
                  Text(tx.paymentMethod?.label ?? 'Paid', style: t.caption),
                ],
              ),
            ),
            LuxeAmount(tx.amount, fit: false, style: t.number.copyWith(fontSize: 14)),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronRight, size: 15, color: p.inkMute),
          ],
        ),
      ),
    );
  }
}
