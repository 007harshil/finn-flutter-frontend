import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../auth/application/auth_controller.dart';
import '../../friends/domain/finn_id.dart';
import '../../auth/domain/auth_session.dart';
import '../../settings/domain/financial_profile.dart';
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
    return LedgerPage(
      appBar: const LedgerAppBar(title: 'Profile'),
      storageKey: 'profile',
      slivers: [
        SliverToBoxAdapter(
          child: loading
              ? const LedgerPageSkeleton(rows: 4)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageColumn(
                      top: Sp.xl,
                      child: _Identity(profile: profile, session: session),
                    ),
                    PageColumn(
                      top: Sp.section,
                      child: _FinancialSection(profile: profile),
                    ),
                    PageColumn(
                      top: Sp.section,
                      child: _AccountSection(session: session),
                    ),
                    const PageColumn(
                      top: Sp.section,
                      child: _SecuritySection(),
                    ),
                    const PageColumn(
                      top: Sp.section,
                      bottom: Sp.xl,
                      child: _DeleteAccount(),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

class _Identity extends StatelessWidget {
  const _Identity({required this.profile, required this.session});

  final FinancialProfile? profile;
  final AuthSession? session;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final name = profile?.displayName.trim() ?? '';
    final email = session?.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ProfileAvatar(name: name, email: email, size: 72),
        const SizedBox(height: Sp.md),
        Semantics(
          header: true,
          child: Text(
            name.isEmpty ? 'Set up your profile' : name,
            style: t.title,
            textAlign: TextAlign.center,
          ),
        ),
        if (email != null) ...[
          const SizedBox(height: 2),
          Text(
            email,
            style: t.label.copyWith(color: c.inkSoft),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: Sp.lg),
        LedgerButton(
          key: const ValueKey('edit-profile'),
          label: profile == null ? 'Set up profile' : 'Edit profile',
          icon: LucideIcons.pencil,
          variant: LedgerButtonVariant.secondary,
          small: true,
          onPressed: () => context.push(AppRoutes.profile),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Financial profile
// ---------------------------------------------------------------------------

class _FinancialSection extends StatelessWidget {
  const _FinancialSection({required this.profile});

  final FinancialProfile? profile;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final p = profile;
    void edit() => context.push(AppRoutes.profile);
    Widget amount(Money m) =>
        AmountText(m, style: t.figureSmall, decimals: DecimalDisplay.none);
    return LedgerSection(
      title: 'Financial profile',
      child: LedgerPanel(
        children: p == null
            ? [
                LedgerRow(
                  leading: const IconWell(icon: LucideIcons.userRoundPlus),
                  title: 'Add your details',
                  subtitle: 'Name, opening balance and start date',
                  chevron: true,
                  onTap: edit,
                ),
              ]
            : [
                LedgerRow(
                  title: 'Opening balance',
                  trailing: amount(p.openingBalance),
                  onTap: edit,
                ),
                LedgerRow(
                  title: 'Tracking since',
                  trailing: Text(
                    DateFormats.dayMonthYear.format(p.openingDate),
                    style: t.figureSmall,
                  ),
                  onTap: edit,
                ),
                LedgerRow(
                  title: 'Monthly income',
                  trailing: p.monthlyIncomeEstimate == null
                      ? Text(
                          'Not set',
                          style: t.body.copyWith(color: context.ink.inkSoft),
                        )
                      : amount(p.monthlyIncomeEstimate!),
                  onTap: edit,
                ),
              ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

class _AccountSection extends ConsumerWidget {
  const _AccountSection({required this.session});

  final AuthSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finnId = ref.watch(friendStateProvider).value?.me?.finnId;
    final c = context.ink;
    final t = context.type;
    final since = session == null
        ? null
        : 'Signed in since ${DateFormats.dayMonthYear.format(session!.signedInAt)}';
    return LedgerSection(
      title: 'Account',
      child: LedgerPanel(
        children: [
          LedgerRow(
            title: 'Sign-in method',
            subtitle: since,
            trailing: Text(
              'Email code',
              style: t.body.copyWith(color: c.inkSoft),
            ),
          ),
          if (finnId != null)
            LedgerRow(
              key: const ValueKey('profile-finn-id'),
              leading: const IconWell(icon: LucideIcons.hash),
              title: 'FiNN ID',
              subtitle: 'Friends add you with this',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(FinnId.format(finnId), style: t.figureSmall),
                  LedgerIconButton(
                    icon: LucideIcons.copy,
                    tooltip: 'Copy FiNN ID',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: FinnId.format(finnId)));
                      if (context.mounted) FinnToast.success(context, 'FiNN ID copied');
                    },
                  ),
                ],
              ),
            ),
          LedgerRow(
            leading: const IconWell(icon: LucideIcons.users),
            title: 'Friends',
            subtitle: 'Add friends and share pending items',
            chevron: true,
            onTap: () => context.push(AppRoutes.friends),
          ),
          LedgerRow(
            leading: const IconWell(icon: LucideIcons.settings),
            title: 'Settings',
            subtitle: 'Privacy, alerts and appearance',
            chevron: true,
            onTap: () => context.push(AppRoutes.settings),
          ),
          LedgerRow(
            leading: const IconWell(icon: LucideIcons.download),
            title: 'Export my data',
            subtitle: 'CSV, JSON or a PDF report',
            chevron: true,
            onTap: () => context.push(AppRoutes.export),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Security: sign out
// ---------------------------------------------------------------------------

class _SecuritySection extends ConsumerStatefulWidget {
  const _SecuritySection();

  @override
  ConsumerState<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<_SecuritySection> {
  bool _busy = false;

  Future<void> _signOut() async {
    if (_busy) return;
    final ok = await showFinnConfirm(
      context,
      title: 'Sign out?',
      message:
          'You will need to sign in again with an email code to see your finances. '
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
    return LedgerSection(
      title: 'Security',
      child: LedgerPanel(
        children: [
          LedgerRow(
            key: const ValueKey('sign-out'),
            leading: const IconWell(icon: LucideIcons.logOut),
            title: 'Sign out',
            trailing: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _busy ? null : _signOut,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Delete account
// ---------------------------------------------------------------------------

class _DeleteAccount extends StatelessWidget {
  const _DeleteAccount();

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Column(
      children: [
        LedgerButton(
          key: const ValueKey('delete-account'),
          label: 'Delete account',
          variant: LedgerButtonVariant.quiet,
          color: c.red,
          onPressed: () => startAccountDeletion(context),
        ),
        const SizedBox(height: Sp.xs),
        Text(
          'Your money data stays on this device.',
          style: t.label.copyWith(color: c.inkFaint),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
