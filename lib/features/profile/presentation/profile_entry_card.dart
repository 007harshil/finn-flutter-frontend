import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../kit/kit.dart';
import '../../auth/application/auth_controller.dart';
import 'profile_avatar.dart';

/// Signed-in account summary at the top of the More tab; opens the profile.
class ProfileEntryCard extends ConsumerWidget {
  const ProfileEntryCard({super.key, this.onTap});

  /// Overrides opening the profile (the side drawer closes itself first).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authControllerProvider)?.email;
    final name = ref.watch(profileStreamProvider).value?.displayName.trim();
    final hasName = name != null && name.isNotEmpty;
    return LedgerPanel(
      key: const ValueKey('profile-entry'),
      children: [
        LedgerRow(
          leading: ProfileAvatar(name: name, email: email, size: 40),
          title: hasName ? name : 'Your profile',
          subtitle: email ?? 'Account and sign-in',
          chevron: true,
          semanticLabel:
              'Profile, ${hasName ? name : 'not set up'}${email == null ? '' : ', $email'}. Open',
          onTap: onTap ?? () => context.push(AppRoutes.account),
        ),
      ],
    );
  }
}
