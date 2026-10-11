import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../design_system/design_system.dart';

/// A titled group of settings rows inside one card.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(icon: icon, title: title, tileColor: color, subtitle: subtitle),
        const SizedBox(height: Space.x3),
        FinnCard(
          padding: const EdgeInsets.symmetric(vertical: Space.x1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const FinnDivider(indent: Space.x4),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Small rounded icon tile used at the start of settings rows.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon({super.key, required this.icon, this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconTile(
      icon: icon,
      background: c.surfaceMuted,
      foreground: color ?? c.textSecondary,
      size: 32,
      radius: Radii.md,
      iconSize: 16,
    );
  }
}

class _RowLayout extends StatelessWidget {
  const _RowLayout({required this.icon, required this.title, this.subtitle, this.trailing, this.iconColor, this.titleColor});

  final IconData icon;
  final Color? iconColor;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2_5),
        child: Row(
          children: [
            SettingsIcon(icon: icon, color: iconColor),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: t.bodyStrong.copyWith(color: titleColor)),
                  if (subtitle != null) ...[
                    const SizedBox(height: Space.x0_5),
                    Text(subtitle!, style: t.caption),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: Space.x2), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Tappable row that opens another screen or sheet.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.titleColor,
    this.showChevron = true,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: _RowLayout(
          icon: icon,
          iconColor: iconColor,
          title: title,
          titleColor: titleColor,
          subtitle: subtitle,
          trailing: showChevron ? Icon(LucideIcons.chevronRight, size: 16, color: c.textTertiary) : null,
        ),
      ),
    );
  }
}

/// On/off row; the whole row toggles.
class SettingsSwitchRow extends ConsumerWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void toggle(bool v) {
      if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.selectionClick();
      onChanged(v);
    }

    return MergeSemantics(
      child: InkWell(
        onTap: () => toggle(!value),
        child: _RowLayout(
          icon: icon,
          iconColor: iconColor,
          title: title,
          subtitle: subtitle,
          trailing: Switch.adaptive(value: value, onChanged: toggle),
        ),
      ),
    );
  }
}

/// Numeric value with − / + buttons.
class SettingsStepperRow extends StatelessWidget {
  const SettingsStepperRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.step = 1,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int value) format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final label = format(value);
    final canDown = value - step >= min;
    final canUp = value + step <= max;
    final stepper = ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FinnIconButton(
            icon: LucideIcons.minus,
            tooltip: 'Decrease $title',
            variant: FinnIconButtonVariant.outline,
            onPressed: canDown ? () => onChanged(value - step) : null,
          ),
          SizedBox(
            width: 72,
            child: Text(label, style: t.bodyStrong, textAlign: TextAlign.center),
          ),
          FinnIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Increase $title',
            variant: FinnIconButtonVariant.outline,
            onPressed: canUp ? () => onChanged(value + step) : null,
          ),
        ],
      ),
    );
    return Semantics(
      label: title,
      value: label,
      increasedValue: canUp ? format(value + step) : null,
      decreasedValue: canDown ? format(value - step) : null,
      onIncrease: canUp ? () => onChanged(value + step) : null,
      onDecrease: canDown ? () => onChanged(value - step) : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow phones: put the stepper under the label.
          if (constraints.maxWidth >= 380) {
            return _RowLayout(icon: icon, title: title, subtitle: subtitle, trailing: stepper);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RowLayout(icon: icon, title: title, subtitle: subtitle),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4 + 32 + Space.x3, 0, Space.x4, Space.x2_5),
                child: Align(alignment: AlignmentDirectional.centerStart, child: stepper),
              ),
            ],
          );
        },
      ),
    );
  }
}
