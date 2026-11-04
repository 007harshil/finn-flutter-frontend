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
    final c = context.ink;
    final t = context.type;
    // Bahi: the signed-in person on a small indigo slab.
    return Semantics(
      key: const ValueKey('profile-entry'),
      button: true,
      label: 'Profile, ${hasName ? name : 'not set up'}${email == null ? '' : ', $email'}. Open',
      excludeSemantics: true,
      child: Material(
        color: c.deep,
        borderRadius: Rad.rMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap ?? () => context.push(AppRoutes.account),
          child: Padding(
            padding: const EdgeInsets.all(Sp.md + 2),
            child: Row(
              children: [
                ProfileAvatar(name: name, email: email, size: 44),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasName ? name : 'Your profile',
                        style: t.bodyStrong.copyWith(color: Slab.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (email != null)
                        Text(email, style: t.small.copyWith(color: Slab.soft), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Slab.soft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
