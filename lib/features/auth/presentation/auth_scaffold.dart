import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_system/design_system.dart';

/// Shared layout for the sign-in screens: brand bar, a narrow scrolling
/// column and an optional pinned footer.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.footer, this.onBack});

  final Widget child;
  final Widget? footer;

  /// Shows a back button in the brand bar when set.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 448,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x2, Space.x2, Space.gutter, 0),
                child: SizedBox(
                  height: Dimens.minTouch,
                  child: Row(
                    children: [
                      if (onBack != null)
                        FinnIconButton(icon: LucideIcons.arrowLeft, tooltip: 'Back', onPressed: onBack)
                      else
                        const SizedBox(width: Space.x2),
                      const Spacer(),
                      Text('FiNN', style: t.title.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(Space.x6, Space.x6, Space.x6, Space.x4),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: child,
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, Space.x4),
                  child: footer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon, eyebrow, title and body at the top of an auth screen.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.icon, required this.eyebrow, required this.title, required this.body});

  final IconData icon;
  final String eyebrow;
  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconTile(icon: icon, background: c.primary, foreground: c.onPrimary, size: 56, radius: Radii.xl, iconSize: 26),
        const SizedBox(height: Space.x6),
        Text(eyebrow, style: t.eyebrow.copyWith(color: c.attention)),
        const SizedBox(height: Space.x2),
        Semantics(header: true, child: Text(title, style: t.display)),
        const SizedBox(height: Space.x3),
        DefaultTextStyle.merge(style: t.body.copyWith(color: c.textSecondary, fontSize: 16), child: body),
      ],
    );
  }
}

/// Small lock note under the auth forms.
class AuthPrivacyNote extends StatelessWidget {
  const AuthPrivacyNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(LucideIcons.lock, size: 13, color: c.textTertiary),
        ),
        const SizedBox(width: Space.x2),
        Expanded(child: Text(text, style: t.caption)),
      ],
    );
  }
}
