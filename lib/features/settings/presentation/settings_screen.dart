import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../application/data_reset.dart';
import '../domain/app_settings.dart';
import '../domain/financial_profile.dart';
import 'settings_widgets.dart';

/// App preferences, profile, privacy, alerts and data management.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = <Widget>[
      const _ProfileCard(),
      const _AppearanceGroup(),
      const _PrivacyGroup(),
      const _MoneyGroup(),
      const _DataGroup(),
      const _Footer(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: CustomScrollView(
        key: const PageStorageKey('settings'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, Space.x2, 0, Space.x10),
            sliver: SliverList.separated(
              itemCount: sections.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.section),
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

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final value = ref.watch(profileStreamProvider);
    if (!value.hasValue && !value.hasError) {
      return const SkeletonPulse(child: CardSkeleton(height: 96));
    }
    final FinancialProfile? p = value.value;
    final name = p?.displayName.trim() ?? '';
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return FinnCard(
      onTap: () => context.push(AppRoutes.profile),
      semanticLabel: p == null ? 'Set up your profile' : 'Profile, $name. Edit',
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Text(initial, style: t.title.copyWith(color: c.primary)),
          ),
          const SizedBox(width: Space.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p == null ? 'Set up your profile' : name, style: t.title),
                const SizedBox(height: Space.x0_5),
                if (p == null)
                  Text('Add your name and starting balance', style: t.caption)
                else ...[
                  Text('Tracking since ${DateFormats.dayMonthYear.format(p.openingDate)}', style: t.caption),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Opening balance ', style: t.caption),
                      AmountText(
                        p.openingBalance,
                        style: t.caption.copyWith(color: c.textPrimary, fontWeight: FontWeight.w600),
                        decimals: DecimalDisplay.none,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Icon(LucideIcons.squarePen, size: 18, color: c.textTertiary),
        ],
      ),
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
    final c = context.colors;
    final t = context.text;
    final theme = ref.watch(settingsProvider.select((s) => s.theme));
    final motion = ref.watch(settingsProvider.select((s) => s.motion));
    final ctrl = ref.read(settingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(icon: LucideIcons.palette, title: 'Appearance', tileColor: c.accentAnalytics),
        const SizedBox(height: Space.x3),
        FinnCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Theme', style: t.label),
              const SizedBox(height: Space.x2),
              SegmentedTabs<ThemePreference>(
                items: [for (final p in ThemePreference.values) SegmentItem(p, p.label)],
                selected: theme,
                onChanged: (v) => ctrl.update((s) => s.copyWith(theme: v)),
              ),
              const SizedBox(height: Space.x4),
              Text('Animations', style: t.label),
              const SizedBox(height: Space.x2),
              SegmentedTabs<MotionPreference>(
                items: [for (final p in MotionPreference.values) SegmentItem(p, p.label)],
                selected: motion,
                onChanged: (v) => ctrl.update((s) => s.copyWith(motion: v)),
              ),
              const SizedBox(height: Space.x1_5),
              Text('Reduced keeps movement to a minimum.', style: t.caption),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Privacy & feel
// ---------------------------------------------------------------------------

class _PrivacyGroup extends ConsumerWidget {
  const _PrivacyGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final hide = ref.watch(settingsProvider.select((s) => s.hideBalances));
    final haptics = ref.watch(settingsProvider.select((s) => s.hapticsEnabled));
    final ctrl = ref.read(settingsProvider.notifier);
    return SettingsGroup(
      title: 'Privacy & feel',
      icon: LucideIcons.shieldCheck,
      color: c.primary,
      children: [
        SettingsSwitchRow(
          key: const ValueKey('hide-balances'),
          icon: hide ? LucideIcons.eyeOff : LucideIcons.eye,
          title: 'Hide balances',
          subtitle: 'Mask amounts across the app in public places',
          value: hide,
          onChanged: (v) => ctrl.update((s) => s.copyWith(hideBalances: v)),
        ),
        SettingsSwitchRow(
          key: const ValueKey('haptics'),
          icon: LucideIcons.vibrate,
          title: 'Haptic feedback',
          subtitle: 'Gentle vibrations on taps and confirmations',
          value: haptics,
          onChanged: (v) => ctrl.update((s) => s.copyWith(hapticsEnabled: v)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Money & alerts
// ---------------------------------------------------------------------------

class _MoneyGroup extends ConsumerWidget {
  const _MoneyGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final paise = ref.watch(settingsProvider.select((s) => s.showPaise));
    final startDay = ref.watch(settingsProvider.select((s) => s.monthStartDay));
    final disabled = ref.watch(settingsProvider.select((s) => s.disabledAlertTypes.length));
    final ctrl = ref.read(settingsProvider.notifier);
    return SettingsGroup(
      title: 'Money & alerts',
      icon: LucideIcons.slidersHorizontal,
      color: c.accentBudgets,
      children: [
        SettingsStepperRow(
          key: const ValueKey('month-start'),
          icon: LucideIcons.calendarDays,
          title: 'Budget month starts',
          subtitle: 'Useful if your salary arrives mid-month',
          value: startDay,
          min: 1,
          max: 28,
          format: _ordinal,
          onChanged: (v) => ctrl.update((s) => s.copyWith(monthStartDay: v)),
        ),
        SettingsSwitchRow(
          key: const ValueKey('show-paise'),
          icon: LucideIcons.coins,
          title: 'Show paise',
          subtitle: 'Display amounts to the paisa where it matters',
          value: paise,
          onChanged: (v) => ctrl.update((s) => s.copyWith(showPaise: v)),
        ),
        SettingsNavRow(
          icon: LucideIcons.bell,
          title: 'Alerts & reminders',
          subtitle: disabled == 0 ? 'All alerts on' : '$disabled alert type${disabled == 1 ? '' : 's'} turned off',
          onTap: () => context.push(AppRoutes.notifications),
        ),
        SettingsNavRow(
          icon: LucideIcons.tags,
          title: 'Categories',
          subtitle: 'How income and spending are grouped',
          onTap: () => context.push(AppRoutes.categories),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class _DataGroup extends ConsumerWidget {
  const _DataGroup();

  Future<void> _loadSample(BuildContext context, WidgetRef ref) async {
    final ok = await showFinnConfirm(
      context,
      title: 'Replace with sample data?',
      message: 'Everything on this device will be replaced with six months of example records. '
          'Export first if you want to keep a copy.',
      confirmLabel: 'Replace data',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(dataResetServiceProvider).loadSampleData();
      if (context.mounted) FinnToast.success(context, 'Sample data loaded');
    } on AppFailure catch (f) {
      if (context.mounted) FinnToast.error(context, 'Could not load sample data', subtitle: f.message);
    } catch (_) {
      if (context.mounted) FinnToast.error(context, 'Could not load sample data', subtitle: 'Nothing was changed.');
    }
  }

  Future<void> _erase(BuildContext context, WidgetRef ref) async {
    final ok = await showFinnConfirm(
      context,
      title: 'Erase all data?',
      message: 'This permanently deletes every transaction, goal, loan and setting stored on this device '
          'and takes you back to setup. This cannot be undone.',
      confirmLabel: 'Erase everything',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(dataResetServiceProvider).eraseEverything();
    } on AppFailure catch (f) {
      if (context.mounted) FinnToast.error(context, 'Could not erase your data', subtitle: f.message);
    } catch (_) {
      if (context.mounted) FinnToast.error(context, 'Could not erase your data', subtitle: 'Please try again.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return SettingsGroup(
      title: 'Your data',
      icon: LucideIcons.database,
      color: c.accentNetWorth,
      children: [
        SettingsNavRow(
          icon: LucideIcons.download,
          title: 'Export data',
          subtitle: 'CSV, JSON or a PDF report',
          onTap: () => context.push(AppRoutes.export),
        ),
        SettingsNavRow(
          icon: LucideIcons.history,
          title: 'Activity log',
          subtitle: 'Changes made in this session',
          onTap: () => context.push(AppRoutes.activity),
        ),
        SettingsNavRow(
          icon: LucideIcons.rotateCcw,
          title: 'Load sample data',
          subtitle: 'Replace your records with example data',
          showChevron: false,
          onTap: () => _loadSample(context, ref),
        ),
        SettingsNavRow(
          icon: LucideIcons.trash2,
          iconColor: c.negative,
          title: 'Erase all data',
          titleColor: c.negative,
          subtitle: 'Start again from scratch',
          showChevron: false,
          onTap: () => _erase(context, ref),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.lock, size: 12, color: c.textTertiary),
            const SizedBox(width: Space.x1_5),
            Flexible(child: Text('Your data stays on this device', style: t.micro, textAlign: TextAlign.center)),
          ],
        ),
        const SizedBox(height: Space.x1),
        Text('FiNN · Made for Indian households', style: t.micro, textAlign: TextAlign.center),
      ],
    );
  }
}
