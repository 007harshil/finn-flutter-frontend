import 'package:flutter/foundation.dart';

import '../../alerts/domain/alert.dart';

enum ThemePreference {
  system('System'),
  light('Light'),
  dark('Dark');

  const ThemePreference(this.label);
  final String label;
}

enum MotionPreference {
  system('Follow system'),
  reduced('Reduced'),
  full('Full');

  const MotionPreference(this.label);
  final String label;
}

/// User preferences. Persisted locally; never contains financial data.
@immutable
class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.system,
    this.motion = MotionPreference.system,
    this.hapticsEnabled = true,
    this.hideBalances = false,
    this.showPaise = false,
    this.monthStartDay = 1,
    this.emiReminderDays = 5,
    this.subscriptionReminderDays = 3,
    this.lowEmergencyCoverageMonths = 3,
    this.defaultBudgetWarningBps = 8000,
    this.disabledAlertTypes = const {},
    this.onboardingComplete = false,
  });

  final ThemePreference theme;
  final MotionPreference motion;
  final bool hapticsEnabled;

  /// Mask amounts throughout the app (privacy in public places).
  final bool hideBalances;

  /// Show paise in lists (amounts are always stored to the paisa).
  final bool showPaise;

  /// Day of month a monthly budget period starts (1–28).
  final int monthStartDay;
  final int emiReminderDays;
  final int subscriptionReminderDays;

  /// Emergency coverage (months) below which an alert is raised.
  final int lowEmergencyCoverageMonths;
  final int defaultBudgetWarningBps;
  final Set<AlertType> disabledAlertTypes;
  final bool onboardingComplete;

  bool isAlertEnabled(AlertType type) => !disabledAlertTypes.contains(type);

  AppSettings copyWith({
    ThemePreference? theme,
    MotionPreference? motion,
    bool? hapticsEnabled,
    bool? hideBalances,
    bool? showPaise,
    int? monthStartDay,
    int? emiReminderDays,
    int? subscriptionReminderDays,
    int? lowEmergencyCoverageMonths,
    int? defaultBudgetWarningBps,
    Set<AlertType>? disabledAlertTypes,
    bool? onboardingComplete,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        motion: motion ?? this.motion,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        hideBalances: hideBalances ?? this.hideBalances,
        showPaise: showPaise ?? this.showPaise,
        monthStartDay: monthStartDay ?? this.monthStartDay,
        emiReminderDays: emiReminderDays ?? this.emiReminderDays,
        subscriptionReminderDays: subscriptionReminderDays ?? this.subscriptionReminderDays,
        lowEmergencyCoverageMonths: lowEmergencyCoverageMonths ?? this.lowEmergencyCoverageMonths,
        defaultBudgetWarningBps: defaultBudgetWarningBps ?? this.defaultBudgetWarningBps,
        disabledAlertTypes: disabledAlertTypes ?? this.disabledAlertTypes,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      );

  Map<String, Object?> toJson() => {
        'theme': theme.name,
        'motion': motion.name,
        'hapticsEnabled': hapticsEnabled,
        'hideBalances': hideBalances,
        'showPaise': showPaise,
        'monthStartDay': monthStartDay,
        'emiReminderDays': emiReminderDays,
        'subscriptionReminderDays': subscriptionReminderDays,
        'lowEmergencyCoverageMonths': lowEmergencyCoverageMonths,
        'defaultBudgetWarningBps': defaultBudgetWarningBps,
        'disabledAlertTypes': disabledAlertTypes.map((e) => e.name).toList(),
        'onboardingComplete': onboardingComplete,
      };

  factory AppSettings.fromJson(Map<String, Object?> j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    int i(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    bool b(String k, bool d) => (j[k] as bool?) ?? d;
    return AppSettings(
      theme: pick(ThemePreference.values, j['theme'], ThemePreference.system),
      motion: pick(MotionPreference.values, j['motion'], MotionPreference.system),
      hapticsEnabled: b('hapticsEnabled', true),
      hideBalances: b('hideBalances', false),
      showPaise: b('showPaise', false),
      monthStartDay: i('monthStartDay', 1).clamp(1, 28),
      emiReminderDays: i('emiReminderDays', 5),
      subscriptionReminderDays: i('subscriptionReminderDays', 3),
      lowEmergencyCoverageMonths: i('lowEmergencyCoverageMonths', 3),
      defaultBudgetWarningBps: i('defaultBudgetWarningBps', 8000),
      disabledAlertTypes: ((j['disabledAlertTypes'] as List?) ?? const [])
          // Pending alert types were renamed when pending items lost due dates.
          .map((e) => switch (e) { 'pendingOverdue' => 'pendingOwed', 'collectDue' => 'collectOwed', _ => e })
          .map((e) => AlertType.values.where((t) => t.name == e).firstOrNull)
          .whereType<AlertType>()
          .toSet(),
      onboardingComplete: b('onboardingComplete', false),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings && mapEquals(other.toJson(), toJson()) &&
      setEquals(other.disabledAlertTypes, disabledAlertTypes);

  @override
  int get hashCode => Object.hash(theme, motion, hideBalances, showPaise, monthStartDay,
      onboardingComplete, disabledAlertTypes.length);
}
