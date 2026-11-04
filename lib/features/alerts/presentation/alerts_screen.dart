import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/result/result.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../domain/alert.dart';
import 'alert_card.dart';

/// Filter groups shown as chips.
enum AlertGroup {
  all('All'),
  loans('Loans'),
  payments('Pending'),
  subscriptions('Subscriptions'),
  spending('Spending'),
  savings('Savings');

  const AlertGroup(this.label);
  final String label;

  static AlertGroup of(AlertType t) => switch (t) {
    AlertType.emiDue || AlertType.emiOverdue => loans,
    AlertType.pendingOwed || AlertType.collectOwed => payments,
    AlertType.subscriptionRenewal ||
    AlertType.subscriptionOverdue => subscriptions,
    AlertType.budgetNearLimit ||
    AlertType.budgetBreached ||
    AlertType.monthlyDeficit => spending,
    AlertType.emergencyFundLow ||
    AlertType.emergencyFundNotSet ||
    AlertType.goalMilestone ||
    AlertType.goalAtRisk => savings,
  };
}

/// "What needs attention" centre: every active alert grouped by severity.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  AlertGroup _group = AlertGroup.all;

  /// Hidden immediately on swipe so the Dismissible leaves the tree before
  /// the repository round-trip completes.
  final Set<String> _hidden = {};

  /// Alerts that were unread when the screen opened (shown as "New").
  Set<String>? _newAtOpen;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<List<FinancialAlert>>>(activeAlertsProvider, (
      _,
      next,
    ) {
      final list = next.value;
      if (list == null) return;
      final read = ref.read(alertInboxProvider).readKeys;
      final unread = {
        for (final a in list)
          if (!read.contains(a.key)) a.key,
      };
      if (_newAtOpen == null) {
        _newAtOpen = unread;
      } else {
        _newAtOpen!.addAll(unread);
      }
      if (unread.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Bookkeeping only: a failed write (offline) is retried next time.
        if (mounted)
          ref.read(alertInboxControllerProvider).markRead(unread).ignore();
      });
    }, fireImmediately: true);
  }

  void _dismiss(FinancialAlert a) {
    setState(() => _hidden.add(a.key));
    ref.read(alertInboxControllerProvider).dismiss(a.key).catchError((
      Object e,
    ) {
      if (!mounted) return;
      setState(() => _hidden.remove(a.key));
      FinnToast.error(
        context,
        'Could not dismiss the alert',
        subtitle: e is AppFailure ? e.message : null,
      );
    });
    FinnToast.info(
      context,
      'Alert dismissed',
      subtitle: 'You can restore it from the bottom of this list.',
    );
  }

  Future<void> _restore() async {
    try {
      await ref.read(alertInboxControllerProvider).restoreAll();
    } on AppFailure catch (f) {
      if (mounted)
        FinnToast.error(
          context,
          'Could not restore alerts',
          subtitle: f.message,
        );
      return;
    }
    if (!mounted) return;
    setState(_hidden.clear);
    FinnToast.success(context, 'Dismissed alerts restored');
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<FinancialAlert>>(
      value: ref.watch(activeAlertsProvider),
      loading: Scaffold(
        backgroundColor: context.ink.paper,
        body: const SafeArea(child: LedgerPageSkeleton()),
      ),
      builder: (context, all) => _buildList(
        context,
        all.where((a) => !_hidden.contains(a.key)).toList(),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<FinancialAlert> alerts) {
    final t = context.type;
    final present = {for (final a in alerts) AlertGroup.of(a.type)};
    final group = _group == AlertGroup.all || present.contains(_group)
        ? _group
        : AlertGroup.all;
    final filtered = group == AlertGroup.all
        ? alerts
        : alerts.where((a) => AlertGroup.of(a.type) == group).toList();
    final dismissedCount = ref.watch(
      alertInboxProvider.select((s) => s.dismissedKeys.length),
    );

    final sections = <Widget>[];
    for (final sev in AlertSeverity.values) {
      final items = filtered.where((a) => a.severity == sev).toList();
      if (items.isEmpty) continue;
      sections.add(
        PageBlock(
          key: ValueKey('h_${sev.name}'),
          top: sections.isEmpty ? Sp.lg : Sp.section,
          child: LedgerSection(
            title: sev.label,
            count: items.length,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: Sp.md),
                  _item(items[i]),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return LedgerPage(
      storageKey: 'alerts',
      appBar: const LedgerAppBar(title: 'Needs attention'),
      slivers: [
        if (alerts.isNotEmpty) PageBlock(top: Sp.sm, child: _SeverityDonut(alerts: alerts)),
        if (present.length > 1)
          PageBlock(
            top: Sp.sm,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final g in AlertGroup.values)
                    if (g == AlertGroup.all || present.contains(g)) ...[
                      LedgerChip(
                        label: g.label,
                        selected: g == group,
                        onTap: () => setState(() => _group = g),
                      ),
                      const SizedBox(width: Sp.sm),
                    ],
                ],
              ),
            ),
          ),
        if (sections.isEmpty)
          PageBlock(
            top: Sp.xl,
            child: LedgerEmpty(
              title: 'All clear',
              actionLabel: alerts.isEmpty ? null : 'Show all alerts',
              onAction: alerts.isEmpty
                  ? null
                  : () => setState(() => _group = AlertGroup.all),
            ),
          )
        else
          ...sections,
        if (sections.isNotEmpty || dismissedCount > 0)
          PageBlock(
            top: Sp.xl,
            child: Column(
              children: [
                if (sections.isNotEmpty)
                  Text(
                    'Swipe left to dismiss an alert.',
                    style: t.label,
                    textAlign: TextAlign.center,
                  ),
                if (dismissedCount > 0)
                  LedgerButton(
                    label: 'Restore dismissed',
                    icon: LucideIcons.rotateCcw,
                    variant: LedgerButtonVariant.quiet,
                    small: true,
                    onPressed: _restore,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _item(FinancialAlert a) {
    final card = AlertCard(
      alert: a,
      unread: _newAtOpen?.contains(a.key) ?? false,
    );
    if (!a.dismissible) return KeyedSubtree(key: ValueKey(a.key), child: card);
    return Dismissible(
      key: ValueKey('d_${a.key}'),
      direction: DismissDirection.endToStart,
      background: const _DismissBackground(),
      onDismissed: (_) => _dismiss(a),
      child: Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Dismiss alert'): () =>
              _dismiss(a),
        },
        child: card,
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    return Container(
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
      decoration: BoxDecoration(color: c.sunken, borderRadius: Rad.rLg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Dismiss', style: context.type.labelStrong),
          const SizedBox(width: Sp.sm),
          Icon(LucideIcons.x, size: 16, color: c.ink),
        ],
      ),
    );
  }
}

/// How many alerts sit at each level, as one donut with counted keys.
class _SeverityDonut extends StatelessWidget {
  const _SeverityDonut({required this.alerts});

  final List<FinancialAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    Color hue(AlertSeverity s) => switch (s) {
      AlertSeverity.critical => c.red,
      AlertSeverity.warning => c.amber,
      AlertSeverity.info => c.info,
      AlertSeverity.positive => c.green,
    };
    final counts = {for (final s in AlertSeverity.values) s: alerts.where((a) => a.severity == s).length};
    final shown = [for (final s in AlertSeverity.values) if (counts[s]! > 0) s];
    final urgent = counts[AlertSeverity.critical]!;
    return KhataPanel(
      child: Row(
        children: [
          KhataDonut(
            size: 96,
            stroke: 13,
            parts: [for (final s in shown) BarPart(counts[s]!.toDouble(), hue(s))],
            semanticLabel: [for (final s in shown) '${counts[s]} ${s.label}'].join(', '),
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${alerts.length}', style: t.figure.copyWith(fontSize: 20)),
                Text('alerts', style: t.small),
              ],
            ),
          ),
          const SizedBox(width: Sp.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KhataStamp(label: urgent > 0 ? '$urgent urgent' : 'Nothing urgent', color: urgent > 0 ? c.red : c.green),
                const SizedBox(height: Sp.sm),
                for (final s in shown)
                  KhataKey(color: hue(s), label: '${s.label} · ${counts[s]}', value: const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
