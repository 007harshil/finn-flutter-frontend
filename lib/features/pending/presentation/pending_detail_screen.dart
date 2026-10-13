import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart'
    show
        AmountText,
        AmountVisibility,
        AnimatedAmount,
        BottomClearanceX,
        FinnMenuItem,
        FinnSheetScaffold,
        showFinnActionMenu,
        showFinnSheet;
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../application/pending_actions.dart';
import '../domain/pending_payment.dart';
import 'pending_split_ui.dart';
import 'pending_ui.dart';

enum _Menu { edit, remind, writeOff, delete }

/// One pending item: what is left and how long it has waited, the action
/// that closes it, the bill or shared link it belongs to, then its details
/// and settlements.
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
          label: otherCreated ? 'Edit — only $first can, they added it' : 'Edit details',
          icon: LucideIcons.pencil,
          enabled: !otherCreated,
        ),
        if (v.status.isActive && !p.direction.isOwe)
          const FinnMenuItem(value: _Menu.remind, label: 'Send a reminder', icon: LucideIcons.send),
        if (v.status.isActive)
          FinnMenuItem(
            value: _Menu.writeOff,
            label: canWriteOff ? 'Write off what is left' : 'Write off — only $first can, they are owed',
            icon: LucideIcons.ban,
            enabled: canWriteOff,
          ),
        FinnMenuItem(
          value: _Menu.delete,
          label: otherCreated
              ? 'Delete — only $first can'
              : (hasSettlements ? 'Delete — unavailable, settlements exist' : 'Delete'),
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
        await runAction(
          context,
          ref,
          action: const CancelPendingAction(),
          input: PendingIdInput(id: v.payment.id),
          idempotencyKey: '$_key-off',
        );
      case _Menu.delete:
        final done = await runAction(
          context,
          ref,
          action: const DeletePendingAction(),
          input: PendingIdInput(id: v.payment.id),
          idempotencyKey: '$_key-del',
        );
        if (done != null && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(pendingViewProvider(widget.id));
    final v = value.value;
    return UiPage(
      title: v?.payment.counterparty ?? 'Money owed',
      actions: [
        if (v != null) UiIconButton(icon: LucideIcons.ellipsis, tooltip: 'More actions', onPressed: () => _menu(v)),
      ],
      body: AsyncView<PendingView?>(
        value: value,
        loading: const _Placeholder(),
        builder: (context, v) {
          if (v == null) {
            return Center(
              child: UiEmpty(
                icon: LucideIcons.searchX,
                title: 'This item no longer exists',
                action: 'Back to money owed',
                onAction: () => context.go(AppRoutes.pending),
              ),
            );
          }
          final split = v.payment.split == null ? null : ref.watch(pendingSplitsProvider)[v.payment.split!.id];
          return _Body(view: v, split: split);
        },
      ),
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
    final s = split;
    return ListView(
      key: PageStorageKey('pending-${p.id}'),
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.sm, UiSpace.gutter, context.bottomClearance),
      children: [
        UiColumnWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiReveal(index: 0, child: _Hero(view: v)),
              if (v.status.isActive) ...[
                const SizedBox(height: UiSpace.xl),
                Row(
                  children: [
                    Expanded(
                      child: UiPrimaryButton(
                        label: 'Settle up',
                        onPressed: () => context.push(AppRoutes.settlePending(p.id)),
                      ),
                    ),
                    if (!p.direction.isOwe) ...[
                      const SizedBox(width: UiSpace.md),
                      Expanded(
                        child: Builder(
                          builder: (context) => UiSecondaryButton(
                            label: 'Remind',
                            icon: LucideIcons.send,
                            onPressed: () => sharePendingReminder(context, v),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (s != null)
                UiSection(
                  title: 'Split · ${s.people} people',
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: UiSpace.sm),
                    child: Text(s.methodLabel, style: UiType.of(context).label),
                  ),
                  child: PendingSplitCard(split: s, currentId: p.id),
                ),
              if (p.isShared) _Shared(view: v),
              _Details(view: v),
              _Settlements(view: v),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final v = view;
    final p = v.payment;
    final status = pendingStatus(c, v);
    final (String label, Money headline, String caption) = switch (v.status) {
      PendingStatus.settled => ('Settled with ${p.counterparty}', p.originalAmount, status.label),
      PendingStatus.cancelled => ('Written off', p.originalAmount - v.settled, p.direction.sentence(p.counterparty)),
      _ => (
        p.direction.sentence(p.counterparty),
        v.outstanding,
        'Waiting ${pendingDays(v.daysOpen).toLowerCase()} · since ${DateFormats.dayMonth.format(p.createdDate)}',
      ),
    };
    return UiHero(
      label: label,
      value: AnimatedAmount(headline, style: t.amount, fit: true, animateOnMount: true),
      caption: caption,
      captionColor: v.status.isActive ? status.color : null,
      footer: v.status == PendingStatus.open
          ? null
          : UiProgressFooter(
        value: v.settledBps / 10000,
        color: c.positive,
        semanticsLabel: 'Settled so far',
        start: '${v.settledBps ~/ 100}% settled',
        end: 'of ${_masked(context, p.originalAmount)}',
      ),
    );
  }
}

String _masked(BuildContext context, Money m) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : AmountText.formatted(m);

/// Both sides of a shared item: who added it, and what the other person's
/// FiNN shows right now.
class _Shared extends ConsumerWidget {
  const _Shared({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final p = view.payment;
    final link = p.link!;
    final first = p.counterparty.split(' ').first;
    final mirror = ref.watch(mirrorProvider(link));
    final theirs = mirror?.view(view.today);
    final inStep = theirs != null && theirs.outstanding == view.outstanding && theirs.status == view.status;
    return UiSection(
      title: 'Shared on FiNN',
      child: UiPanelList(
        key: const ValueKey('pending-shared-card'),
        children: [
          UiDetailRow(label: 'With', value: link.handle),
          UiDetailRow(label: 'Added by', value: link.createdByMe ? 'You' : first),
          if (theirs == null)
            UiListRow(onTap: null, title: 'On $first’s FiNN', subtitle: 'Waiting to sync…')
          else
            UiListRow(
              key: const ValueKey('pending-their-side'),
              title: theirs.payment.direction.sentence(theirs.payment.counterparty),
              subtitle: inStep ? 'Both sides match' : 'Syncing with $first',
              subtitleColor: inStep ? c.positive : c.warning,
              semanticLabel: 'See $first’s side',
              trailing: AmountText(theirs.outstanding, style: t.figureSmall),
              onTap: () => showFinnSheet<void>(
                context,
                builder: (_) => _TheirSideSheet(mirror: mirror!, today: view.today, name: first),
              ),
            ),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final p = v.payment;
    final notes = p.notes?.trim() ?? '';
    return UiSection(
      title: 'Details',
      child: UiPanelList(
        children: [
          UiDetailRow(label: 'For', value: p.purpose),
          UiDetailRow(label: 'Reason', value: p.kind.label),
          UiDetailRow(label: 'Started', value: DateFormats.dayMonthYear.format(p.createdDate)),
          if (!v.status.isActive)
            UiDetailRow(
              label: 'Was open',
              value: pendingDays(daysBetween(p.createdDate, v.settledOn ?? p.updatedAt)),
            ),
          if (notes.isNotEmpty) UiNoteRow(label: 'Note', text: notes),
        ],
      ),
    );
  }
}

/// Settlements newest first, each with what was left after it.
class _Settlements extends StatelessWidget {
  const _Settlements({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final v = view;
    // Remaining after each settlement, computed oldest first.
    final left = <String, Money>{};
    var remaining = v.payment.originalAmount;
    for (final s in v.settlements.reversed) {
      remaining = Money.max(remaining - s.amount, Money.zero);
      left[s.id] = remaining;
    }
    final owe = v.payment.direction.isOwe;
    return UiSection(
      title: 'Settlements',
      child: v.settlements.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(left: UiSpace.xs),
              child: Text(v.status.isActive ? 'Nothing settled yet' : 'None recorded', style: t.label),
            )
          : UiPanelList(
              ruleIndent: 64,
              children: [
                for (final s in v.settlements)
                  Builder(
                    key: ValueKey(s.id),
                    builder: (context) {
                      final after = left[s.id]!;
                      final txId = s.transactionId;
                      final note = s.note?.trim() ?? '';
                      return UiListRow(
                        leading: UiMark(icon: LucideIcons.check, color: c.positive),
                        title: '${owe ? 'Paid' : 'Received'} · ${DateFormats.dayMonth.format(s.date)}',
                        subtitle: [
                          after.isZero ? 'Cleared' : '${_masked(context, after)} left',
                          if (s.method != null) s.method!.label,
                          if (note.isNotEmpty) note,
                        ].join(' · '),
                        trailing: AmountText(s.amount, style: t.figureSmall),
                        onTap: txId == null ? null : () => context.push(AppRoutes.transaction(txId)),
                      );
                    },
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
    final t = UiType.of(context);
    final v = mirror.view(today);
    return FinnSheetScaffold(
      title: '$name’s FiNN',
      description: 'What ${mirror.payment.link!.handle} sees for this item. Read-only.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiPanel(child: PendingRow(view: v, onTap: () {})),
          if (v.settlements.isNotEmpty) ...[
            const SizedBox(height: UiSpace.lg),
            Text('Settlements on their side', style: t.label),
            const SizedBox(height: UiSpace.xs),
            UiPanelList(
              children: [
                for (final s in v.settlements)
                  UiListRow(
                    onTap: null,
                    title: DateFormats.dayMonthYear.format(s.date),
                    trailing: AmountText(s.amount, style: t.figureSmall),
                  ),
              ],
            ),
          ],
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
            UiPlaceholder(width: 180, height: 40),
            SizedBox(height: UiSpace.lg),
            UiPlaceholder(height: 6),
            SizedBox(height: UiSpace.xl),
            UiPlaceholder(height: 52, radius: UiRadius.control),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 200, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
