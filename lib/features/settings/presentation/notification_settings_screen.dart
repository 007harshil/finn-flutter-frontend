import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../kit/kit.dart';
import '../../alerts/domain/alert.dart';

/// Which in-app alerts FiNN raises and how early reminders appear.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LedgerPage(
      storageKey: 'notification-settings',
      appBar: const LedgerAppBar(title: 'Alerts & reminders'),
      slivers: [
        const PageBlock(top: Sp.sm, child: _TimingGroup()),
        for (final g in _alertGroups)
          PageBlock(
            top: Sp.section,
            child: _AlertTypeGroup(group: g),
          ),
        const PageBlock(top: Sp.section, child: _RestoreDismissed()),
      ],
    );
  }
}

String _days(int d) => d == 1 ? '1 day' : '$d days';

class _TimingGroup extends ConsumerWidget {
  const _TimingGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    return LedgerSection(
      title: 'Timing',
      child: LedgerPanel(
        children: [
          _StepperRow(
            key: const ValueKey('emi-days'),
            title: 'EMI reminder',
            value: s.emiReminderDays,
            min: 1,
            max: 15,
            format: _days,
            onChanged: (v) =>
                ctrl.update((x) => x.copyWith(emiReminderDays: v)),
          ),
          _StepperRow(
            key: const ValueKey('subscription-days'),
            title: 'Renewal reminder',
            value: s.subscriptionReminderDays,
            min: 1,
            max: 15,
            format: _days,
            onChanged: (v) =>
                ctrl.update((x) => x.copyWith(subscriptionReminderDays: v)),
          ),
          _StepperRow(
            key: const ValueKey('budget-warning'),
            title: 'Budget warning',
            value: s.defaultBudgetWarningBps,
            min: 5000,
            max: 9500,
            step: 500,
            format: (v) => formatBps(v, decimals: 0),
            onChanged: (v) =>
                ctrl.update((x) => x.copyWith(defaultBudgetWarningBps: v)),
          ),
          _StepperRow(
            key: const ValueKey('emergency-months'),
            title: 'Emergency fund low',
            value: s.lowEmergencyCoverageMonths,
            min: 1,
            max: 12,
            format: (v) => v == 1 ? '1 month' : '$v months',
            onChanged: (v) =>
                ctrl.update((x) => x.copyWith(lowEmergencyCoverageMonths: v)),
          ),
        ],
      ),
    );
  }
}

/// Label and current value with - / + steppers; stacks on narrow screens.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.step = 1,
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int value) format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final label = format(value);
    final canDown = value - step >= min;
    final canUp = value + step <= max;
    final c = context.ink;
    final text = Text(title, style: t.bodyStrong);
    // Bahi stepper: one sunken pill, the value as a condensed figure.
    final stepper = ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(color: c.sunken, borderRadius: Rad.rBtn),
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LedgerIconButton(
            icon: LucideIcons.minus,
            tooltip: 'Decrease $title',
            onPressed: canDown ? () => onChanged(value - step) : null,
          ),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: t.figure,
              textAlign: TextAlign.center,
            ),
          ),
          LedgerIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Increase $title',
            onPressed: canUp ? () => onChanged(value + step) : null,
          ),
        ],
        ),
      ),
    );
    return Semantics(
      label: title,
      value: label,
      increasedValue: canUp ? format(value + step) : null,
      decreasedValue: canDown ? format(value - step) : null,
      onIncrease: canUp ? () => onChanged(value + step) : null,
      onDecrease: canDown ? () => onChanged(value - step) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm),
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 300
              ? Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: Sp.md),
                    stepper,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    text,
                    const SizedBox(height: Sp.xs),
                    Align(alignment: Alignment.centerRight, child: stepper),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AlertGroup {
  const _AlertGroup(this.title, this.types);
  final String title;
  final List<AlertType> types;
}

const _alertGroups = [
  _AlertGroup('Loans and EMIs', [AlertType.emiDue, AlertType.emiOverdue]),
  _AlertGroup('Pending payments', [
    AlertType.pendingOwed,
    AlertType.collectOwed,
  ]),
  _AlertGroup('Subscriptions', [
    AlertType.subscriptionRenewal,
    AlertType.subscriptionOverdue,
  ]),
  _AlertGroup('Budgets and spending', [
    AlertType.budgetNearLimit,
    AlertType.budgetBreached,
    AlertType.monthlyDeficit,
  ]),
  _AlertGroup('Savings', [
    AlertType.emergencyFundLow,
    AlertType.emergencyFundNotSet,
    AlertType.goalMilestone,
    AlertType.goalAtRisk,
  ]),
];


class _AlertTypeGroup extends ConsumerWidget {
  const _AlertTypeGroup({required this.group});
  final _AlertGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disabled = ref.watch(
      settingsProvider.select((s) => s.disabledAlertTypes),
    );
    final ctrl = ref.read(settingsProvider.notifier);
    return LedgerSection(
      title: group.title,
      child: LedgerPanel(
        children: [
          for (final type in group.types)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: LedgerSwitchRow(
                key: ValueKey('alert-${type.name}'),
                title: type.label,
                value: !disabled.contains(type),
                onChanged: (on) => ctrl.update(
                  (s) => s.copyWith(
                    disabledAlertTypes: on
                        ? ({...s.disabledAlertTypes}..remove(type))
                        : {...s.disabledAlertTypes, type},
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RestoreDismissed extends ConsumerWidget {
  const _RestoreDismissed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(
      alertInboxProvider.select((s) => s.dismissedKeys.length),
    );
    if (dismissed == 0) return const SizedBox.shrink();
    return LedgerButton(
      label:
          'Show $dismissed dismissed alert${dismissed == 1 ? '' : 's'} again',
      icon: LucideIcons.rotateCcw,
      variant: LedgerButtonVariant.secondary,
      expand: true,
      onPressed: () async {
        try {
          await runWithLoader(context, () => ref.read(alertInboxControllerProvider).restoreAll());
        } on AppFailure catch (f) {
          if (context.mounted)
            FinnToast.error(
              context,
              'Could not restore alerts',
              subtitle: f.message,
            );
          return;
        }
        if (context.mounted)
          FinnToast.success(context, 'Dismissed alerts restored');
      },
    );
  }
}
