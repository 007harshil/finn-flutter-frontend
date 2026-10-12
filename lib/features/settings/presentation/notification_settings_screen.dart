import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../design_system/design_system.dart';
import '../../alerts/domain/alert.dart';
import 'settings_widgets.dart';

/// Which in-app alerts FiNN raises and how early reminders appear.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = <Widget>[
      const InfoBanner(
        tone: FinnTone.info,
        message: 'Alerts appear on Home under "What needs attention". '
            'Overdue items are always worth a look, but you can turn any type off.',
      ),
      const _TimingGroup(),
      for (final g in _alertGroups) _AlertTypeGroup(group: g),
      const _RestoreDismissed(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts & reminders')),
      body: CustomScrollView(
        key: const PageStorageKey('notification-settings'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, Space.x2, 0, Space.x10),
            sliver: SliverList.separated(
              itemCount: sections.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.x6),
              itemBuilder: (context, i) => ResponsiveCenter(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: StaggeredEntrance(index: i, child: sections[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _days(int d) => d == 1 ? '1 day' : '$d days';

class _TimingGroup extends ConsumerWidget {
  const _TimingGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    return SettingsGroup(
      title: 'Timing & thresholds',
      icon: LucideIcons.clock,
      color: c.primary,
      children: [
        SettingsStepperRow(
          key: const ValueKey('emi-days'),
          icon: LucideIcons.landmark,
          title: 'EMI reminder',
          subtitle: 'Days before an EMI is due',
          value: s.emiReminderDays,
          min: 1,
          max: 15,
          format: _days,
          onChanged: (v) => ctrl.update((x) => x.copyWith(emiReminderDays: v)),
        ),
        SettingsStepperRow(
          key: const ValueKey('subscription-days'),
          icon: LucideIcons.repeat,
          title: 'Renewal reminder',
          subtitle: 'Days before a subscription renews',
          value: s.subscriptionReminderDays,
          min: 1,
          max: 15,
          format: _days,
          onChanged: (v) => ctrl.update((x) => x.copyWith(subscriptionReminderDays: v)),
        ),
        SettingsStepperRow(
          key: const ValueKey('budget-warning'),
          icon: LucideIcons.chartPie,
          title: 'Budget warning',
          subtitle: 'Alert when this much of a budget is used',
          value: s.defaultBudgetWarningBps,
          min: 5000,
          max: 9500,
          step: 500,
          format: (v) => formatBps(v, decimals: 0),
          onChanged: (v) => ctrl.update((x) => x.copyWith(defaultBudgetWarningBps: v)),
        ),
        SettingsStepperRow(
          key: const ValueKey('emergency-months'),
          icon: LucideIcons.shieldCheck,
          title: 'Emergency fund low',
          subtitle: 'Alert when it covers fewer months of expenses',
          value: s.lowEmergencyCoverageMonths,
          min: 1,
          max: 12,
          format: (v) => v == 1 ? '1 month' : '$v months',
          onChanged: (v) => ctrl.update((x) => x.copyWith(lowEmergencyCoverageMonths: v)),
        ),
      ],
    );
  }
}

class _AlertGroup {
  const _AlertGroup(this.title, this.icon, this.types);
  final String title;
  final IconData icon;
  final List<AlertType> types;
}

const _alertGroups = [
  _AlertGroup('Loans & EMIs', LucideIcons.landmark, [AlertType.emiDue, AlertType.emiOverdue]),
  _AlertGroup('Pending payments', LucideIcons.handCoins, [AlertType.pendingOwed, AlertType.collectOwed]),
  _AlertGroup('Subscriptions', LucideIcons.repeat, [AlertType.subscriptionRenewal, AlertType.subscriptionOverdue]),
  _AlertGroup('Budgets & spending', LucideIcons.chartPie,
      [AlertType.budgetNearLimit, AlertType.budgetBreached, AlertType.monthlyDeficit]),
  _AlertGroup('Savings', LucideIcons.piggyBank, [
    AlertType.emergencyFundLow,
    AlertType.emergencyFundNotSet,
    AlertType.goalMilestone,
    AlertType.goalAtRisk,
  ]),
];

String _describe(AlertType t) => switch (t) {
      AlertType.emiDue => 'Before an EMI is due',
      AlertType.emiOverdue => 'When an EMI date has passed unpaid',
      AlertType.pendingOwed => 'When money you owe is unpaid for over 21 days',
      AlertType.collectOwed => 'When money owed to you is unpaid for over 21 days',
      AlertType.subscriptionRenewal => 'Before a subscription renews',
      AlertType.subscriptionOverdue => 'When a renewal has not been paid',
      AlertType.budgetNearLimit => 'When a budget reaches your warning level',
      AlertType.budgetBreached => 'When spending goes over a budget',
      AlertType.monthlyDeficit => 'When this month\'s spending is above income',
      AlertType.emergencyFundLow => 'When your safety net is below your threshold',
      AlertType.emergencyFundNotSet => 'Reminder to set up an emergency fund',
      AlertType.goalMilestone => 'When a goal reaches a milestone',
      AlertType.goalAtRisk => 'When a goal falls behind its target date',
    };

class _AlertTypeGroup extends ConsumerWidget {
  const _AlertTypeGroup({required this.group});
  final _AlertGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final disabled = ref.watch(settingsProvider.select((s) => s.disabledAlertTypes));
    final ctrl = ref.read(settingsProvider.notifier);
    return SettingsGroup(
      title: group.title,
      icon: group.icon,
      color: c.attention,
      children: [
        for (final type in group.types)
          SettingsSwitchRow(
            key: ValueKey('alert-${type.name}'),
            icon: disabled.contains(type) ? LucideIcons.bellOff : LucideIcons.bell,
            title: type.label,
            subtitle: _describe(type),
            value: !disabled.contains(type),
            onChanged: (on) => ctrl.update((s) => s.copyWith(
                  disabledAlertTypes: on ? ({...s.disabledAlertTypes}..remove(type)) : {...s.disabledAlertTypes, type},
                )),
          ),
      ],
    );
  }
}

class _RestoreDismissed extends ConsumerWidget {
  const _RestoreDismissed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(alertInboxProvider.select((s) => s.dismissedKeys.length));
    if (dismissed == 0) return const SizedBox.shrink();
    return FinnButton(
      label: 'Show $dismissed dismissed alert${dismissed == 1 ? '' : 's'} again',
      icon: LucideIcons.rotateCcw,
      variant: FinnButtonVariant.outline,
      expand: true,
      onPressed: () async {
        try {
          await ref.read(alertInboxControllerProvider).restoreAll();
        } on AppFailure catch (f) {
          if (context.mounted) FinnToast.error(context, 'Could not restore alerts', subtitle: f.message);
          return;
        }
        if (context.mounted) FinnToast.success(context, 'Dismissed alerts restored');
      },
    );
  }
}
