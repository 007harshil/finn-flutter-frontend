import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../application/data_reset.dart';
import '../domain/app_settings.dart';
import '../domain/financial_profile.dart';
import 'settings_widgets.dart';

/// App preferences, profile, privacy, alerts and data management.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const LedgerPage(
      storageKey: 'settings',
      appBar: LedgerAppBar(title: 'Settings'),
      slivers: [
        PageBlock(top: Sp.xl, child: _ProfileRow()),
        PageBlock(top: Sp.section, child: _AppearanceGroup()),
        PageBlock(top: Sp.section, child: _PrivacyGroup()),
        PageBlock(top: Sp.section, child: _MoneyGroup()),
        PageBlock(top: Sp.section, child: _DataGroup()),
        PageBlock(top: Sp.section, bottom: Sp.xl, child: _Footer()),
      ],
    );
  }
}

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class _ProfileRow extends ConsumerWidget {
  const _ProfileRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(profileStreamProvider);
    if (!value.hasValue && !value.hasError) {
      return const LedgerSkeleton(height: 72, radius: Rad.lg);
    }
    final FinancialProfile? p = value.value;
    final name = p?.displayName.trim() ?? '';
    return LedgerPanel(
      children: [
        LedgerRow(
          leading: ProfileAvatar(name: name, email: null, size: 44),
          title: p == null ? 'Set up your profile' : name,
          subtitle: p == null
              ? 'Add your name and starting balance'
              : 'Tracking since ${DateFormats.dayMonthYear.format(p.openingDate)}',
          chevron: true,
          semanticLabel:
              p == null ? 'Set up your profile' : 'Profile, $name. Edit',
          onTap: () => context.push(AppRoutes.profile),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

class _AppearanceGroup extends ConsumerWidget {
  const _AppearanceGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final theme = ref.watch(settingsProvider.select((s) => s.theme));
    final motion = ref.watch(settingsProvider.select((s) => s.motion));
    final ctrl = ref.read(settingsProvider.notifier);
    Widget choice(String label, Widget control) => Padding(
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: t.bodyStrong),
          const SizedBox(height: Sp.sm),
          control,
        ],
      ),
    );
    return LedgerSection(
      title: 'Appearance',
      child: LedgerPanel(
        children: [
          choice(
            'Theme',
            LedgerSegmented<ThemePreference>(
              segments: [
                for (final p in ThemePreference.values)
                  LedgerSegment(p, p.label),
              ],
              selected: theme,
              onChanged: (v) => ctrl.update((s) => s.copyWith(theme: v)),
            ),
          ),
          choice(
            'Animations',
            LedgerSegmented<MotionPreference>(
              segments: [
                for (final p in MotionPreference.values)
                  LedgerSegment(p, p.label),
              ],
              selected: motion,
              onChanged: (v) => ctrl.update((s) => s.copyWith(motion: v)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyGroup extends ConsumerWidget {
  const _PrivacyGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(settingsProvider.select((s) => s.hideBalances));
    final haptics = ref.watch(settingsProvider.select((s) => s.hapticsEnabled));
    final ctrl = ref.read(settingsProvider.notifier);
    return LedgerSection(
      title: 'Privacy & feel',
      child: LedgerPanel(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: LedgerSwitchRow(
              key: const ValueKey('hide-balances'),
              title: 'Hide balances',
              subtitle: 'Mask amounts across the app',
              value: hide,
              onChanged: (v) => ctrl.update((s) => s.copyWith(hideBalances: v)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: LedgerSwitchRow(
              key: const ValueKey('haptics'),
              title: 'Haptic feedback',
              subtitle: 'Gentle vibration on taps',
              value: haptics,
              onChanged: (v) =>
                  ctrl.update((s) => s.copyWith(hapticsEnabled: v)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyGroup extends ConsumerWidget {
  const _MoneyGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paise = ref.watch(settingsProvider.select((s) => s.showPaise));
    final startDay = ref.watch(settingsProvider.select((s) => s.monthStartDay));
    final disabled = ref.watch(
      settingsProvider.select((s) => s.disabledAlertTypes.length),
    );
    final ctrl = ref.read(settingsProvider.notifier);
    return LedgerSection(
      title: 'Money & alerts',
      child: LedgerPanel(
        children: [
          SettingsStepperRow(
            key: const ValueKey('month-start'),
            title: 'Budget month starts',
            subtitle: 'Useful if your salary arrives mid-month',
            value: startDay,
            min: 1,
            max: 28,
            format: _ordinal,
            onChanged: (v) => ctrl.update((s) => s.copyWith(monthStartDay: v)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: LedgerSwitchRow(
              key: const ValueKey('show-paise'),
              title: 'Show paise',
              subtitle: 'Amounts to the paisa where it matters',
              value: paise,
              onChanged: (v) => ctrl.update((s) => s.copyWith(showPaise: v)),
            ),
          ),
          LedgerRow(
            leading: const IconWell(icon: LucideIcons.bell),
            title: 'Alerts & reminders',
            subtitle: disabled == 0
                ? 'All alerts on'
                : '$disabled alert type${disabled == 1 ? '' : 's'} turned off',
            chevron: true,
            onTap: () => context.push(AppRoutes.notifications),
          ),
          LedgerRow(
            leading: const IconWell(icon: LucideIcons.tags),
            title: 'Categories',
            chevron: true,
            onTap: () => context.push(AppRoutes.categories),
          ),
        ],
      ),
    );
  }
}

class _DataGroup extends ConsumerWidget {
  const _DataGroup();

  Future<void> _loadSample(BuildContext context, WidgetRef ref) async {
    final ok = await showFinnConfirm(
      context,
      title: 'Replace with sample data?',
      message:
          'Everything on this device will be replaced with six months of example records. '
          'Export first if you want to keep a copy.',
      confirmLabel: 'Replace data',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(dataResetServiceProvider).loadSampleData();
      if (context.mounted) FinnToast.success(context, 'Sample data loaded');
    } on AppFailure catch (f) {
      if (context.mounted) {
        FinnToast.error(context, 'Could not load sample data', subtitle: f.message);
      }
    } catch (_) {
      if (context.mounted) {
        FinnToast.error(context, 'Could not load sample data', subtitle: 'Nothing was changed.');
      }
    }
  }

  Future<void> _erase(BuildContext context, WidgetRef ref) async {
    final ok = await showFinnConfirm(
      context,
      title: 'Erase all data?',
      message:
          'This permanently deletes every transaction, goal, loan and setting stored on this device '
          'and takes you back to setup. This cannot be undone.',
      confirmLabel: 'Erase everything',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(dataResetServiceProvider).eraseEverything();
    } on AppFailure catch (f) {
      if (context.mounted) {
        FinnToast.error(context, 'Could not erase your data', subtitle: f.message);
      }
    } catch (_) {
      if (context.mounted) {
        FinnToast.error(context, 'Could not erase your data', subtitle: 'Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerSection(
          title: 'Your data',
          child: LedgerPanel(
            children: [
              LedgerRow(
                leading: const IconWell(icon: LucideIcons.download),
                title: 'Export data',
                subtitle: 'CSV, JSON or a PDF report',
                chevron: true,
                onTap: () => context.push(AppRoutes.export),
              ),
              LedgerRow(
                leading: const IconWell(icon: LucideIcons.history),
                title: 'Activity log',
                subtitle: 'Changes made in this session',
                chevron: true,
                onTap: () => context.push(AppRoutes.activity),
              ),
              LedgerRow(
                leading: const IconWell(icon: LucideIcons.rotateCcw),
                title: 'Load sample data',
                subtitle: 'Replace your records with examples',
                onTap: () => _loadSample(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.lg),
        LedgerButton(
          key: const ValueKey('erase-all'),
          label: 'Erase all data',
          icon: LucideIcons.trash2,
          variant: LedgerButtonVariant.quiet,
          color: c.red,
          onPressed: () => _erase(context, ref),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.ink;
    return Text(
      'Your data stays on this device.\nFiNN · Made for Indian households',
      style: t.label.copyWith(color: c.inkFaint),
      textAlign: TextAlign.center,
    );
  }
}
