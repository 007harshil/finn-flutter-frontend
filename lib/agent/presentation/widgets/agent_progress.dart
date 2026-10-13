import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../ui/ui.dart';

/// Small spinner for agent work; a still clock under reduced motion so
/// nothing animates forever.
class AgentSpinner extends StatelessWidget {
  const AgentSpinner({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    if (UiMotion.of(context).reduced) {
      return Icon(LucideIcons.loader, size: size, color: c.inkSoft);
    }
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(strokeWidth: 2, color: c.inkSoft),
    );
  }
}

/// "Understanding your request…": what the agent is doing right now.
class AgentWorkingLine extends StatelessWidget {
  const AgentWorkingLine({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: UiSpace.touch),
        child: Row(
          children: [
            const SizedBox(width: 2),
            const AgentSpinner(),
            const SizedBox(width: UiSpace.md),
            Expanded(child: Text(label, style: t.label)),
          ],
        ),
      ),
    );
  }
}
