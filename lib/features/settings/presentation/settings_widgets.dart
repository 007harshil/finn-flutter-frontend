import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../kit/kit.dart';

/// Numeric setting as a [LedgerRow] with - / + buttons. Stacks the buttons
/// under the label on narrow screens.
class SettingsStepperRow extends StatelessWidget {
  const SettingsStepperRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.step = 1,
    this.subtitle,
  });

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
    final t = context.type;
    final label = format(value);
    final canDown = value - step >= min;
    final canUp = value + step <= max;
    final stepper = ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LedgerIconButton(
            icon: LucideIcons.minus,
            tooltip: 'Decrease $title',
            onPressed: canDown ? () => onChanged(value - step) : null,
          ),
          SizedBox(
            width: 64,
            child: Text(label, style: t.bodyStrong, textAlign: TextAlign.center),
          ),
          LedgerIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Increase $title',
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
        builder: (context, box) {
          final wide = box.maxWidth >= 380;
          return LedgerRow(
            title: title,
            subtitle: subtitle,
            subtitleLines: 2,
            trailing: wide ? stepper : null,
            below: wide
                ? null
                : Align(alignment: Alignment.centerRight, child: stepper),
          );
        },
      ),
    );
  }
}
