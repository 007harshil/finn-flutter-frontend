import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../domain/alert.dart';
import 'alert_card.dart';

/// Filter groups shown as chips.
enum AlertGroup {
  all('All', LucideIcons.layers),
  loans('Loans & EMIs', LucideIcons.landmark),
  payments('Pending', LucideIcons.handCoins),
  subscriptions('Subscriptions', LucideIcons.repeat),
  spending('Spending', LucideIcons.chartPie),
  savings('Savings', LucideIcons.piggyBank);

  const AlertGroup(this.label, this.icon);
  final String label;
  final IconData icon;

  static AlertGroup of(AlertType t) => switch (t) {
    AlertType.emiDue || AlertType.emiOverdue => loans,
    AlertType.pendingOwed || AlertType.collectOwed => payments,
    AlertType.subscriptionRenewal || AlertType.subscriptionOverdue => subscriptions,
    AlertType.budgetNearLimit || AlertType.budgetBreached || AlertType.monthlyDeficit => spending,
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
    ref.listenManual<AsyncValue<List<FinancialAlert>>>(activeAlertsProvider, (_, next) {
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
        if (mounted) ref.read(alertInboxControllerProvider).markRead(unread);
      });
    }, fireImmediately: true);
  }

  void _dismiss(FinancialAlert a) {
    setState(() => _hidden.add(a.key));
    ref.read(alertInboxControllerProvider).dismiss(a.key);
    FinnToast.info(context, 'Alert dismissed', subtitle: 'You can restore it from the bottom of this list.');
  }

  Future<void> _restore() async {
    await ref.read(alertInboxControllerProvider).restoreAll();
    if (!mounted) return;
    setState(_hidden.clear);
    FinnToast.success(context, 'Dismissed alerts restored');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('What needs attention')),
      body: AsyncView<List<FinancialAlert>>(
        value: ref.watch(activeAlertsProvider),
        loading: const SkeletonPulse(child: ListSkeleton(count: 4, rowHeight: 148)),
        builder: (context, all) => _buildList(context, all.where((a) => !_hidden.contains(a.key)).toList()),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<FinancialAlert> alerts) {
    final c = context.colors;
    final t = context.text;
    final present = {for (final a in alerts) AlertGroup.of(a.type)};
    final group = _group == AlertGroup.all || present.contains(_group) ? _group : AlertGroup.all;
    final filtered = group == AlertGroup.all ? alerts : alerts.where((a) => AlertGroup.of(a.type) == group).toList();
    final dismissedCount = ref.watch(alertInboxProvider.select((s) => s.dismissedKeys.length));

    final entries = <Object>[];
    for (final sev in AlertSeverity.values) {
      final items = filtered.where((a) => a.severity == sev).toList();
      if (items.isEmpty) continue;
      entries.add(_SeverityHeader(sev, items.length));
      entries.addAll(items);
    }

    return CustomScrollView(
      key: const PageStorageKey<String>('alerts'),
      slivers: [
        SliverToBoxAdapter(
          child: ResponsiveCenter(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.gutter, Space.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(LucideIcons.smartphone, size: 14, color: c.textTertiary),
                ),
                const SizedBox(width: Space.x1_5),
                Expanded(
                  child: Text(
                    'Alerts are generated on this device from your data. Push notifications are not enabled yet.',
                    style: t.caption.copyWith(color: c.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (present.length > 1)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: FilterChipBar<AlertGroup>(
                multiSelect: false,
                items: [
                  for (final g in AlertGroup.values)
                    if (g == AlertGroup.all || present.contains(g)) FilterChipItem(g, g.label, icon: g.icon),
                ],
                selected: {group},
                onChanged: (s) => setState(() => _group = s.isEmpty ? AlertGroup.all : s.first),
              ),
            ),
          ),
        if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.x6),
              child: Center(
                child: EmptyState(
                  icon: LucideIcons.circleCheck,
                  title: 'All clear',
                  message: alerts.isEmpty
                      ? 'Nothing needs your attention right now. We will surface due dates, budget limits and savings milestones here.'
                      : 'No alerts in this group.',
                  actionLabel: alerts.isEmpty ? null : 'Show all alerts',
                  onAction: alerts.isEmpty ? null : () => setState(() => _group = AlertGroup.all),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                if (e is _SeverityHeader) {
                  return ResponsiveCenter(
                    key: ValueKey('h_${e.severity.name}'),
                    child: Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : Space.x4, bottom: Space.x2_5),
                      child: e,
                    ),
                  );
                }
                final a = e as FinancialAlert;
                final card = AlertCard(alert: a, unread: _newAtOpen?.contains(a.key) ?? false);
                return ResponsiveCenter(
                  key: ValueKey(a.key),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Space.x2_5),
                    child: a.dismissible
                        ? Dismissible(
                            key: ValueKey('d_${a.key}'),
                            direction: DismissDirection.endToStart,
                            background: const _DismissBackground(),
                            onDismissed: (_) => _dismiss(a),
                            child: Semantics(
                              customSemanticsActions: {
                                const CustomSemanticsAction(label: 'Dismiss alert'): () => _dismiss(a),
                              },
                              child: card,
                            ),
                          )
                        : card,
                  ),
                );
              },
            ),
          ),
        SliverToBoxAdapter(
          child: ResponsiveCenter(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, Space.x10),
            child: Column(
              children: [
                if (entries.isNotEmpty)
                  Text('Swipe left on an alert to dismiss it.', style: t.micro, textAlign: TextAlign.center),
                if (dismissedCount > 0)
                  TextButton.icon(
                    onPressed: _restore,
                    icon: const Icon(LucideIcons.rotateCcw, size: 14),
                    label: const Text('Restore dismissed'),
                    style: TextButton.styleFrom(
                      foregroundColor: c.textSecondary,
                      minimumSize: const Size(Dimens.minTouch, Dimens.minTouch),
                      textStyle: t.label.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SeverityHeader extends StatelessWidget {
  const _SeverityHeader(this.severity, this.count);

  final AlertSeverity severity;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final color = severity.color(c);
    return Semantics(
      header: true,
      child: Row(
        children: [
          Icon(severity.icon, size: 15, color: color),
          const SizedBox(width: Space.x1_5),
          Text(severity.label.toUpperCase(), style: t.sectionTitle.copyWith(color: color)),
          const SizedBox(width: Space.x1_5),
          Text('· $count', style: t.label),
        ],
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsets.symmetric(horizontal: Space.x5),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rXl),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Dismiss', style: context.text.label.copyWith(color: c.textPrimary)),
          const SizedBox(width: Space.x1_5),
          Icon(LucideIcons.x, size: 16, color: c.textPrimary),
        ],
      ),
    );
  }
}
