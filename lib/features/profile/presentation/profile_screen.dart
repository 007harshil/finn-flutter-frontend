import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_session.dart';
import '../../settings/domain/financial_profile.dart';
import '../../settings/presentation/settings_widgets.dart';
import 'delete_account_sheet.dart';
import 'profile_avatar.dart';

/// The signed-in person: identity, financial starting point, account,
/// sign-out and account deletion.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(profileStreamProvider);
    final session = ref.watch(authControllerProvider);
    final loading = !value.hasValue && !value.hasError;
    final profile = value.value;
    final sections = <Widget>[
      if (loading)
        const SkeletonPulse(child: CardSkeleton(height: 188))
      else
        _IdentityCard(profile: profile, session: session),
      if (!loading) _StartingPointGroup(profile: profile),
      _AccountGroup(session: session),
      const _SignOutGroup(),
      const _Footer(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: CustomScrollView(
        key: const PageStorageKey('profile'),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(0, Space.x2, 0, Space.x10 + context.safeBottom),
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

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.profile, required this.session});

  final FinancialProfile? profile;
  final AuthSession? session;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final name = profile?.displayName.trim() ?? '';
    final email = session?.email;
    return FinnCard.gradient(
      padding: const EdgeInsets.all(Space.x5),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c.primary.withValues(alpha: c.isDark ? 0.16 : 0.07), c.surface],
      ),
      border: BorderSide(color: c.border),
      child: Column(
        children: [
          ProfileAvatar(name: name, email: email, size: 72),
          const SizedBox(height: Space.x3),
          Semantics(
            header: true,
            child: Text(
              name.isEmpty ? 'Set up your profile' : name,
              style: t.pageTitle,
              textAlign: TextAlign.center,
            ),
          ),
          if (email != null) ...[
            const SizedBox(height: Space.x1),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.mail, size: 13, color: c.textTertiary),
                const SizedBox(width: Space.x1_5),
                Flexible(child: Text(email, style: t.caption, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ],
          if (session != null) ...[
            const SizedBox(height: Space.x3),
            _Badge(
              icon: LucideIcons.badgeCheck,
              label: 'Verified · since ${DateFormats.dayMonthYear.format(session!.signedInAt)}',
            ),
          ],
          const SizedBox(height: Space.x4),
          FinnButton(
            key: const ValueKey('edit-profile'),
            label: profile == null ? 'Set up profile' : 'Edit profile',
            icon: LucideIcons.squarePen,
            variant: FinnButtonVariant.outline,
            size: FinnButtonSize.sm,
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.x2_5, vertical: Space.x1),
      decoration: BoxDecoration(color: c.positiveSoft, borderRadius: Radii.rFull),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c.positive),
          const SizedBox(width: Space.x1),
          Flexible(child: Text(label, style: t.micro.copyWith(color: c.positive, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Starting point
// ---------------------------------------------------------------------------

class _StartingPointGroup extends StatelessWidget {
  const _StartingPointGroup({required this.profile});

  final FinancialProfile? profile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    void edit() => context.push(AppRoutes.profile);
    return SettingsGroup(
      title: 'Starting point',
      subtitle: 'Every balance is worked out from these',
      icon: LucideIcons.flag,
      color: c.accentNetWorth,
      children: p == null
          ? [
              SettingsNavRow(
                icon: LucideIcons.userRoundPlus,
                title: 'Add your details',
                subtitle: 'Name, opening balance and start date',
                onTap: edit,
              ),
            ]
          : [
              _ValueRow(
                icon: LucideIcons.wallet,
                title: 'Opening balance',
                value: _Amount(p.openingBalance),
                onTap: edit,
              ),
              _ValueRow(
                icon: LucideIcons.calendarDays,
                title: 'Tracking since',
                value: Text(DateFormats.dayMonthYear.format(p.openingDate)),
                onTap: edit,
              ),
              _ValueRow(
                icon: LucideIcons.trendingUp,
                title: 'Monthly income',
                value: p.monthlyIncomeEstimate == null ? const Text('Not set') : _Amount(p.monthlyIncomeEstimate!),
                onTap: edit,
              ),
            ],
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount(this.amount);
  final Money amount;

  @override
  Widget build(BuildContext context) =>
      AmountText(amount, style: DefaultTextStyle.of(context).style, decimals: DecimalDisplay.none);
}

/// Label on the left, a value on the right; the row opens [onTap].
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.icon, required this.title, required this.value, this.onTap});

  final IconData icon;
  final String title;
  final Widget value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2_5),
            child: Row(
              children: [
                SettingsIcon(icon: icon),
                const SizedBox(width: Space.x3),
                Expanded(child: Text(title, style: t.bodyStrong)),
                const SizedBox(width: Space.x2),
                Flexible(
                  child: DefaultTextStyle.merge(
                    style: t.body.copyWith(color: c.textSecondary),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: value,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({required this.session});

  final AuthSession? session;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsGroup(
      title: 'Account',
      icon: LucideIcons.userRound,
      color: c.primary,
      children: [
        _ValueRow(
          icon: LucideIcons.mail,
          title: 'Email',
          value: Text(session?.email ?? 'Not signed in'),
        ),
        const _ValueRow(
          icon: LucideIcons.keyRound,
          title: 'Sign-in method',
          value: Text('Email code'),
        ),
        SettingsNavRow(
          icon: LucideIcons.settings,
          title: 'Settings',
          subtitle: 'Privacy, alerts and appearance',
          onTap: () => context.push(AppRoutes.settings),
        ),
        SettingsNavRow(
          icon: LucideIcons.download,
          title: 'Export my data',
          subtitle: 'CSV, JSON or a PDF report',
          onTap: () => context.push(AppRoutes.export),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sign out
// ---------------------------------------------------------------------------

class _SignOutGroup extends ConsumerStatefulWidget {
  const _SignOutGroup();

  @override
  ConsumerState<_SignOutGroup> createState() => _SignOutGroupState();
}

class _SignOutGroupState extends ConsumerState<_SignOutGroup> {
  bool _busy = false;

  Future<void> _signOut() async {
    if (_busy) return;
    final ok = await showFinnConfirm(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again with an email code to see your finances. '
          'Your records stay on this device.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    // Toast first: signing out redirects to the login screen and unmounts
    // this one. The local session is cleared even if the provider fails.
    FinnToast.success(context, 'Signed out', subtitle: 'See you soon.');
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (_) {
      // Already signed out locally.
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsGroup(
      title: 'Security',
      icon: LucideIcons.shield,
      color: c.textSecondary,
      children: [
        _DangerRow(
          key: const ValueKey('sign-out'),
          icon: LucideIcons.logOut,
          label: 'Sign out',
          busy: _busy,
          onTap: _busy ? null : _signOut,
        ),
        _DangerRow(
          key: const ValueKey('delete-account'),
          icon: LucideIcons.userX,
          label: 'Delete account',
          onTap: _busy ? null : () => startAccountDeletion(context),
        ),
      ],
    );
  }
}

/// A red, full-width action row in the Security group.
class _DangerRow extends StatelessWidget {
  const _DangerRow({super.key, required this.icon, required this.label, required this.onTap, this.busy = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2_5),
            child: Row(
              children: [
                SettingsIcon(icon: icon, color: c.negative),
                const SizedBox(width: Space.x3),
                Expanded(child: Text(label, style: context.text.bodyStrong.copyWith(color: c.negative))),
                if (busy)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.negative),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.lock, size: 12, color: c.textTertiary),
        const SizedBox(width: Space.x1_5),
        Flexible(
          child: Text('Your email signs you in. Your money data stays on this device.',
              style: t.micro, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
