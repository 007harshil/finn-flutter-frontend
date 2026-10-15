import 'package:flutter/material.dart';

import '../../../kit/kit.dart';

/// Up to two initials from [name], else the first letter of [email].
String profileInitials(String? name, String? email) {
  final words = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isNotEmpty) {
    return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }
  final e = (email ?? '').trim();
  return e.isEmpty ? '?' : e.characters.first.toUpperCase();
}

/// Initials in a sunken circle.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    required this.email,
    this.size = 52,
  });

  final String? name;
  final String? email;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.sunken, shape: BoxShape.circle),
        child: Text(
          profileInitials(name, email),
          style: t.title.copyWith(
            color: c.ink,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
