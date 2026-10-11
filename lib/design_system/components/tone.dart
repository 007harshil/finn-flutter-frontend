import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens/finn_colors.dart';

/// Semantic tone shared by banners, toasts and status visuals.
enum FinnTone { info, positive, warning, negative }

/// Resolves a [FinnTone] to colours and a default icon.
extension FinnToneX on FinnTone {
  /// Strong tone colour (icons, borders, solid fills).
  Color color(FinnColors c) => switch (this) {
        FinnTone.info => c.info,
        FinnTone.positive => c.positive,
        FinnTone.warning => c.warning,
        FinnTone.negative => c.negative,
      };

  /// Soft tinted background for this tone.
  Color soft(FinnColors c) => switch (this) {
        FinnTone.info => c.infoSoft,
        FinnTone.positive => c.positiveSoft,
        FinnTone.warning => c.warningSoft,
        FinnTone.negative => c.negativeSoft,
      };

  /// Default icon so meaning is never conveyed by colour alone.
  IconData get icon => switch (this) {
        FinnTone.info => LucideIcons.info,
        FinnTone.positive => LucideIcons.circleCheck,
        FinnTone.warning => LucideIcons.triangleAlert,
        FinnTone.negative => LucideIcons.circleAlert,
      };
}

/// Foreground colour for content placed on a solid semantic fill.
extension FinnColorsOnSolidX on FinnColors {
  /// White in light mode, deep navy in dark mode (where fills are lighter).
  Color get onSolid => isDark ? background : surface;
}
