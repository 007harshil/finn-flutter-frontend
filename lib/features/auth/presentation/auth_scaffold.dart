import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../kit/kit.dart';

/// Shared layout for the sign-in screens: wordmark bar, a narrow scrolling
/// column and an optional pinned footer, all on the paper page.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.footer, this.onBack});

  final Widget child;
  final Widget? footer;

  /// Shows a back button in the top bar when set.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.sm, Sp.gutter, 0),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        if (onBack != null)
                          LedgerIconButton(icon: LucideIcons.arrowLeft, tooltip: 'Back', onPressed: onBack)
                        else
                          const SizedBox(width: Sp.md),
                        const Spacer(),
                        Text('FiNN', style: t.heading.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(Sp.gutter + Sp.xs, Sp.xl, Sp.gutter + Sp.xs, Sp.lg),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: child,
                  ),
                ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.md, Sp.gutter, Sp.lg),
                    child: footer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Title and one line of body at the top of an auth screen.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: t.title)),
        const SizedBox(height: Sp.sm),
        DefaultTextStyle.merge(style: t.body.copyWith(color: c.inkSoft), child: body),
      ],
    );
  }
}

/// One quiet line under the auth forms.
class AuthPrivacyNote extends StatelessWidget {
  const AuthPrivacyNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: context.type.small);
}
