import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../design_system/design_system.dart';
import '../../auth/application/auth_controller.dart';
import 'profile_avatar.dart';

/// Signed-in account summary at the top of the More tab; opens the profile.
class ProfileEntryCard extends ConsumerWidget {
  const ProfileEntryCard({super.key, this.onTap});

  /// Overrides opening the profile (the side drawer closes itself first).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final email = ref.watch(authControllerProvider)?.email;
    final name = ref.watch(profileStreamProvider).value?.displayName.trim();
    final hasName = name != null && name.isNotEmpty;
    return FinnCard(
      key: const ValueKey('profile-entry'),
      onTap: onTap ?? () => context.push(AppRoutes.account),
      semanticLabel: 'Profile, ${hasName ? name : 'not set up'}${email == null ? '' : ', $email'}. Open',
      child: Row(
        children: [
          ProfileAvatar(name: name, email: email),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hasName ? name : 'Your profile', style: t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.x0_5),
                Text(email ?? 'Account and sign-in', style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: Space.x2),
          Icon(LucideIcons.chevronRight, size: 16, color: c.textTertiary),
        ],
      ),
    );
  }
}
