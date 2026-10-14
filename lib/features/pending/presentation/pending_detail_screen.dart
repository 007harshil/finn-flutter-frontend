import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../application/pending_actions.dart';
import '../domain/pending_payment.dart';
import 'pending_split_ui.dart';
import 'pending_ui.dart';

enum _Menu { edit, remind, writeOff, delete }

/// One pending item: what is left and how much is settled, the one thing
/// to do next (settle), then the split it belongs to, the shared side, the
/// details and the settlement history.
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
    final p = v.payment;
    final first = p.counterparty.split(' ').first;
    // Shared items: only the creator edits or deletes; only the person who
    // is owed can write it off.
    final otherCreated = p.link != null && !p.link!.createdByMe;
    final canWriteOff = !(p.isShared && p.direction.isOwe);
    final choice = await showFinnActionMenu<_Menu>(
      context,
      title: p.purpose,
      items: [
        FinnMenuItem(
          value: _Menu.edit,
          label: otherCreated ? 'Edit (only $first can, they added it)' : 'Edit details',
          icon: LucideIcons.pencil,
          enabled: !otherCreated,
        ),
        if (v.status.isActive && !p.direction.isOwe)
          const FinnMenuItem(value: _Menu.remind, label: 'Send a reminder', icon: LucideIcons.send),
        if (v.status.isActive)
          FinnMenuItem(
            value: _Menu.writeOff,
            label: canWriteOff ? 'Write off what is left' : 'Write off (only $first can, they are owed)',
            icon: LucideIcons.ban,
            enabled: canWriteOff,
          ),
        FinnMenuItem(
          value: _Menu.delete,
          label: otherCreated
              ? 'Delete (only $first can)'
              : (hasSettlements ? 'Delete (unavailable, settlements exist)' : 'Delete'),
          icon: LucideIcons.trash2,
          destructive: true,
          enabled: !hasSettlements && !otherCreated,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _Menu.edit:
        context.push(AppRoutes.editPending(v.payment.id));
      case _Menu.remind:
        await sharePendingReminder(context, v);
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
    return LedgerPage(
      appBar: LedgerAppBar(
        title: v?.payment.counterparty ?? 'Money owed',
        actions: [
          if (v != null)
            LedgerIconButton(icon: LucideIcons.ellipsisVertical, tooltip: 'More actions', onPressed: () => _menu(v)),
        ],
      ),
      storageKey: 'pending-${widget.id}',
      slivers: [
        SliverToBoxAdapter(
          child: AsyncView<PendingView?>(
            value: value,
            loading: const LedgerPageSkeleton(rows: 3),
            builder: (context, v) {
              if (v == null) {
                return PageColumn(
                  top: Sp.xxl,
                  child: LedgerEmpty(
                    title: 'This item no longer exists',
                    message: 'It may have been deleted.',
                    actionLabel: 'Back to money owed',
                    onAction: () => context.go(AppRoutes.pending),
                  ),
                );
              }
              final split = v.payment.split == null ? null : ref.watch(pendingSplitsProvider)[v.payment.split!.id];
              return _Body(view: v, split: split);
            },
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view, this.split});

  final PendingView view;

  /// The bill this item is part of, when it was split between several people.
  final PendingSplitView? split;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final p = v.payment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageColumn(top: Sp.lg, child: _Hero(view: v)),
        if (split case final split?)
          PageColumn(top: Sp.section, child: PendingSplitSection(split: split, currentId: p.id)),
        if (p.isShared) PageColumn(top: Sp.section, child: _Shared(view: v)),
        PageColumn(top: Sp.section, child: _Details(view: v)),
        PageColumn(top: Sp.section, child: _History(view: v)),
        PageColumn(
          top: Sp.xl,
          child: LedgerNote(
            text: 'Creating this did not change your balance. Settling records the cash movement once.'
                '${v.settlements.isNotEmpty ? ' Items with settlements cannot be deleted, so your history stays accurate. Write off the rest instead.' : ''}',
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// What is left as the one number, how much is settled, how long it has
/// waited, and the settle action.
class _Hero extends StatelessWidget {
  const _Hero({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final v = view;
    final p = v.payment;
    final active = v.status.isActive;
    final (Money headline, String? after) = switch (v.status) {
      PendingStatus.settled => (p.originalAmount, 'settled in full'),
      PendingStatus.cancelled => (p.originalAmount - v.settled, 'written off'),
      PendingStatus.partiallySettled => (v.outstanding, 'left of ${pendingMoney(context, p.originalAmount)}'),
      PendingStatus.open => (v.outstanding, null),
    };
    final settledShare = v.settledBps / 10000;
    final String status;
    Color? tone;
    switch (v.status) {
      case PendingStatus.settled:
        final on = v.settledOn;
        final took = on == null ? 0 : daysBetween(p.createdDate, on);
        status = on == null
            ? 'Settled in full'
            : 'Settled ${DateFormats.dayMonthYear.format(on)}, '
                '${took <= 0 ? 'the day it began' : '${pendingDays(took)} after it began'}';
        tone = c.green;
      case PendingStatus.cancelled:
        status = 'Written off. ${pendingMoney(context, v.settled)} was settled before that.';
      case PendingStatus.open || PendingStatus.partiallySettled:
        status = pendingAgeSentence(v);
        tone = v.isLongPending ? c.amber : null;
    }
    final last = v.daysSinceLastPayment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(p.direction.sentence(p.counterparty), style: t.label),
        const SizedBox(height: Sp.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: AnimatedAmount(
                headline,
                style: t.figureXL.copyWith(color: active && !p.direction.isOwe ? c.green : c.ink),
                fit: true,
                animateOnMount: true,
              ),
            ),
            if (after != null) ...[
              const SizedBox(width: Sp.sm),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(after, style: t.figureSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: Sp.xs),
        Text(p.purpose, style: t.label),
        if (v.settled.isPositive && v.status != PendingStatus.settled) ...[
          const SizedBox(height: Sp.lg),
          LedgerBar(value: settledShare, semanticLabel: '${v.settledBps ~/ 100}% settled'),
          const SizedBox(height: Sp.sm),
          Text(
            '${pendingMoney(context, v.settled)} settled'
            '${last == null || !active ? '' : ', last ${last == 0 ? 'today' : '$last ${last == 1 ? 'day' : 'days'} ago'}'}',
            style: t.label,
          ),
        ],
        const SizedBox(height: Sp.md),
        Text(status, style: t.body.copyWith(color: tone)),
        if (active) ...[
          const SizedBox(height: Sp.xl),
          Row(
            children: [
              Expanded(
                child: LedgerButton(
                  label: 'Settle',
                  icon: LucideIcons.circleCheck,
                  expand: true,
                  onPressed: () => context.push(AppRoutes.settlePending(p.id)),
                ),
              ),
              if (!p.direction.isOwe) ...[
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Builder(
                    builder: (context) => LedgerButton(
                      label: 'Remind',
                      icon: LucideIcons.send,
                      variant: LedgerButtonVariant.secondary,
                      expand: true,
                      onPressed: () => sharePendingReminder(context, v),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared on FiNN
// ---------------------------------------------------------------------------

/// Double entry made visible: who added the shared item and what the other
/// person's FiNN shows right now, with a check that both sides agree.
class _Shared extends ConsumerWidget {
  const _Shared({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final t = context.type;
    final p = view.payment;
    final link = p.link!;
    final first = p.counterparty.split(' ').first;
    final mirror = ref.watch(mirrorProvider(link));
    final theirs = mirror?.view(view.today);
    final inStep = theirs != null && theirs.outstanding == view.outstanding && theirs.status == view.status;
    return LedgerSection(
      key: const ValueKey('pending-shared-card'),
      title: 'Shared on FiNN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerPanel(
            dividerIndent: Sp.lg + 40 + Sp.md + 2,
            children: [
              LedgerRow(
                leading: const IconWell(icon: LucideIcons.link2),
                title: link.handle,
                subtitle: link.createdByMe ? 'Added by you' : 'Added by $first',
              ),
              if (theirs == null)
                const LedgerRow(
                  leading: IconWell(icon: LucideIcons.refreshCw),
                  title: 'Waiting to sync',
                )
              else
                LedgerRow(
                  key: const ValueKey('pending-their-side'),
                  leading: PendingInitials(name: p.counterparty),
                  title: theirs.payment.direction.sentence(theirs.payment.counterparty),
                  subtitle: inStep ? 'Both sides match' : 'Syncing with $first',
                  subtitleColor: inStep ? c.green : c.amber,
                  trailing: AmountText(theirs.outstanding, style: t.figure),
                  chevron: true,
                  semanticLabel: 'On $first’s FiNN: ${theirs.payment.direction.sentence(theirs.payment.counterparty)}. '
                      '${inStep ? 'Both sides match' : 'Syncing'}. Opens their side.',
                  onTap: () => showFinnSheet<void>(
                    context,
                    builder: (_) => _TheirSideSheet(mirror: mirror!, today: view.today, name: first),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Text(
            link.createdByMe
                ? 'In both accounts. You can edit it; either of you can record a settlement.'
                : '$first added this, so only they can edit it. Either of you can record a settlement.',
            style: t.label,
          ),
        ],
      ),
    );
  }
}

/// Read-only view of the mirrored entry, as the other person sees it.
class _TheirSideSheet extends StatelessWidget {
  const _TheirSideSheet({required this.mirror, required this.today, required this.name});

  final MirrorEntry mirror;
  final DateTime today;
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final v = mirror.view(today);
    return FinnSheetScaffold(
      title: '$name’s FiNN',
      description: 'What ${mirror.payment.link!.handle} sees for this item. Read-only.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerPanel(children: [PendingRow(view: v)]),
          const SizedBox(height: Sp.md),
          Text(pendingAgeSentence(v), style: t.label),
          if (v.settlements.isNotEmpty) ...[
            const SizedBox(height: Sp.xl),
            Text('Settlements on their side', style: t.labelStrong),
            const SizedBox(height: Sp.sm),
            LedgerPanel(
              children: [
                for (final s in v.settlements)
                  LedgerRow(
                    title: DateFormats.dayMonthYear.format(s.date),
                    trailing: AmountText(s.amount, style: t.figure),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Details and history
// ---------------------------------------------------------------------------

/// Reason, start date, how long it waited, and the note.
class _Details extends StatelessWidget {
  const _Details({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final p = v.payment;
    final notes = p.notes?.trim() ?? '';
    final waited = v.status.isActive ? v.daysOpen : daysBetween(p.createdDate, v.settledOn ?? p.updatedAt);
    return LedgerSection(
      title: 'Details',
      child: LedgerPanel(
        children: [
          LedgerFact(label: 'Reason', text: p.kind.label),
          LedgerFact(label: 'Began', text: DateFormats.dayMonthYear.format(p.createdDate)),
          LedgerFact(label: v.status.isActive ? 'Waiting' : 'Was open', text: pendingDays(waited)),
          if (notes.isNotEmpty) LedgerFact(label: 'Note', text: notes, stacked: true),
        ],
      ),
    );
  }
}

/// Settlements newest first, each with what was left after it.
class _History extends StatelessWidget {
  const _History({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final v = view;
    final owe = v.payment.direction.isOwe;
    // Remaining after each settlement, computed oldest first.
    final left = <String, Money>{};
    var remaining = v.payment.originalAmount;
    for (final s in v.settlements.reversed) {
      remaining = Money.max(remaining - s.amount, Money.zero);
      left[s.id] = remaining;
    }
    return LedgerSection(
      title: 'Settlements',
      count: v.settlements.isEmpty ? null : v.settlements.length,
      child: v.settlements.isEmpty
          ? Text(v.status.isActive ? 'Nothing settled yet.' : 'No settlements were recorded.', style: t.label)
          : LedgerPanel(
              dividerIndent: Sp.lg + 40 + Sp.md + 2,
              children: [
                for (final s in v.settlements)
                  _SettlementRow(
                    settlement: s,
                    owe: owe,
                    leftAfter: left[s.id]!,
                    amountColor: owe ? c.ink : c.green,
                  ),
              ],
            ),
    );
  }
}

class _SettlementRow extends StatelessWidget {
  const _SettlementRow({
    required this.settlement,
    required this.owe,
    required this.leftAfter,
    required this.amountColor,
  });

  final PendingSettlement settlement;
  final bool owe;
  final Money leftAfter;
  final Color amountColor;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final s = settlement;
    final txId = s.transactionId;
    final note = s.note?.trim() ?? '';
    final sub = [
      DateFormats.dayMonthYear.format(s.date),
      if (s.method != null) s.method!.label,
      if (txId == null) 'outside your tracked cash',
      if (note.isNotEmpty) note,
    ].join(', ');
    final leftLabel = leftAfter.isZero
        ? 'cleared'
        : '${AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : leftAfter.format()} left';
    return LedgerRow(
      key: ValueKey(s.id),
      leading: IconWell(icon: owe ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft),
      title: owe ? 'You paid' : 'You received',
      subtitle: sub,
      subtitleLines: 2,
      trailing: AmountText(s.amount, style: t.figure.copyWith(color: amountColor)),
      trailingSub: Text(leftLabel, style: t.small),
      chevron: txId != null,
      onTap: txId == null ? null : () => context.push(AppRoutes.transaction(txId)),
      semanticLabel: '${owe ? 'You paid' : 'You received'} ${pendingSpoken(context, s.amount)}. $sub. '
          '${leftAfter.isZero ? 'Cleared' : '${pendingSpoken(context, leftAfter)} left'}.'
          '${txId == null ? '' : ' Opens the linked transaction.'}',
    );
  }
}
