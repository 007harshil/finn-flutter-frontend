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
import '../../../shared/presentation/push_then_leave.dart';
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
    // is owed can settle or write it off.
    final otherCreated = p.link != null && !p.link!.createdByMe;
    final canWriteOff = p.canSettle;
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
        final done = await runAction(context, ref,
            action: const CancelPendingAction(), input: PendingIdInput(id: v.payment.id), idempotencyKey: '$_key-off');
        if (done != null && mounted && context.canPop()) context.pop();
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
        PageColumn(top: Sp.lg, child: _Details(view: v)),
        PageColumn(top: Sp.section, child: _History(view: v)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// What is left as the one number on the slab, the settled share as a
/// ring, how long it has waited, and the settle action.
class _Hero extends StatelessWidget {
  const _Hero({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final p = v.payment;
    final active = v.status.isActive;
    final Money headline = switch (v.status) {
      PendingStatus.settled => p.originalAmount,
      PendingStatus.cancelled => p.originalAmount - v.settled,
      _ => v.outstanding,
    };
    final settledShare = v.settledBps / 10000;
    final waited = active ? v.daysOpen : daysBetween(p.createdDate, v.settledOn ?? p.updatedAt);
    final tone = switch (v.status) {
      PendingStatus.settled => SlabTone.good,
      PendingStatus.cancelled => SlabTone.neutral,
      _ => v.isLongPending ? SlabTone.warn : SlabTone.neutral,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BahiSlab(
          leading: p.direction.isOwe ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft,
          label: p.direction.sentence(p.counterparty),
          figure: SlabFigure(headline, color: active && !p.direction.isOwe ? Slab.good : null),
          caption: p.purpose,
          stamp: SlabStamp(label: v.status.label, tone: tone),
          visual: SlabRing(
            value: settledShare,
            size: 96,
            color: Slab.good,
            top: '${v.settledBps ~/ 100}%',
            bottom: 'settled',
            semanticLabel: '${v.settledBps ~/ 100}% settled',
          ),
          stats: [
            SlabStat.money(label: 'Of', amount: p.originalAmount),
            if (v.settled.isPositive) SlabStat.money(label: 'Settled', amount: v.settled, color: Slab.good),
            SlabStat(
              label: active ? 'Waiting' : 'Was open',
              value: Text(
                pendingDays(waited),
                style: context.type.figure.copyWith(color: active && v.isLongPending ? Slab.warn : Slab.ink),
              ),
            ),
          ],
        ),
        if (active) ...[
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(
                child: LedgerButton(
                  label: p.canSettle ? 'Settle' : 'Only ${p.counterparty.split(' ').first} can settle',
                  icon: LucideIcons.circleCheck,
                  expand: true,
                  onPressed: p.canSettle ? () => pushThenLeave(context, AppRoutes.settlePending(p.id)) : null,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FactTags(
          tags: [
            p.kind.label,
            'Began ${DateFormats.dayMonthYear.format(p.createdDate)}',
            if (!v.status.isActive) 'Open ${pendingDays(waited)}',
          ],
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          LedgerNote(icon: LucideIcons.stickyNote, text: notes),
        ],
      ],
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
          ? const LedgerEmpty(icon: LucideIcons.hourglass, title: 'Nothing settled yet')
          : LedgerPanel(
              khata: true,
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
      if (s.channel != null) s.channel!,
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
