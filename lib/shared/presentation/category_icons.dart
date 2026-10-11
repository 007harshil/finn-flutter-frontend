import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_system/design_system.dart';
import '../../features/categories/domain/category.dart';

/// Maps persisted icon keys to icons. Keys are stable strings so stored
/// records never depend on icon code points.
abstract final class CategoryIcons {
  static const Map<String, IconData> byKey = {
    'utensils': LucideIcons.utensils,
    'shoppingCart': LucideIcons.shoppingCart,
    'home': LucideIcons.house,
    'zap': LucideIcons.zap,
    'car': LucideIcons.car,
    'shoppingBag': LucideIcons.shoppingBag,
    'clapperboard': LucideIcons.clapperboard,
    'heartPulse': LucideIcons.heartPulse,
    'graduationCap': LucideIcons.graduationCap,
    'plane': LucideIcons.plane,
    'sparkles': LucideIcons.sparkles,
    'gift': LucideIcons.gift,
    'shieldCheck': LucideIcons.shieldCheck,
    'repeat': LucideIcons.repeat,
    'users': LucideIcons.users,
    'dumbbell': LucideIcons.dumbbell,
    'briefcase': LucideIcons.briefcase,
    'laptop': LucideIcons.laptop,
    'percent': LucideIcons.percent,
    'receipt': LucideIcons.receipt,
    'building': LucideIcons.building,
    'scale': LucideIcons.scale,
    'handCoins': LucideIcons.handCoins,
    'handshake': LucideIcons.handshake,
    'circleDot': LucideIcons.circleDot,
    'landmark': LucideIcons.landmark,
    'gem': LucideIcons.gem,
    'package': LucideIcons.package,
    'trendingUp': LucideIcons.trendingUp,
    'heart': LucideIcons.heart,
    'target': LucideIcons.target,
    'wallet': LucideIcons.wallet,
    'tag': LucideIcons.tag,
  };

  /// Keys offered in the category icon picker.
  static List<String> get pickable => byKey.keys.toList(growable: false);

  static IconData of(String? key) => byKey[key] ?? LucideIcons.tag;
}

/// Icon tile for a category (handles missing/deleted categories).
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 40});

  final TransactionCategory? category;
  final double size;

  @override
  Widget build(BuildContext context) => CategoryIconTile(
        icon: CategoryIcons.of(category?.iconKey),
        colorIndex: category?.colorIndex ?? 6,
        size: size,
        radius: size * 0.3,
      );
}
