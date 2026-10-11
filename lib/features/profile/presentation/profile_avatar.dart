import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';

/// Up to two initials from [name], else the first letter of [email].
String profileInitials(String? name, String? email) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isNotEmpty) {
    return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }
  final e = (email ?? '').trim();
  return e.isEmpty ? '?' : e.characters.first.toUpperCase();
}

/// Round initials avatar in the primary tint.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, required this.email, this.size = 52});

  final String? name;
  final String? email;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.primary.withValues(alpha: c.isDark ? 0.32 : 0.16), c.primary.withValues(alpha: c.isDark ? 0.18 : 0.06)],
          ),
          border: Border.all(color: c.primary.withValues(alpha: 0.24)),
        ),
        child: Text(
          profileInitials(name, email),
          style: t.title.copyWith(color: c.primary, fontSize: size * 0.36, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
