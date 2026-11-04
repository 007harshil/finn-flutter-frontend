import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/category_icons.dart';
import '../domain/goal.dart';

/// Small pieces shared by the goals tab and the goal detail screen.

/// Whole-rupee money for sentences, masked when balances are hidden.
String goalMoney(BuildContext context, Money m) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : MoneyFormatter.format(m, decimals: DecimalDisplay.none);

/// "31%".
String goalPercent(double share) => '${(share * 100).round()}%';

/// "Mar 2027".
final DateFormat goalMonth = DateFormat('MMM yyyy');

/// "about a month" / "about 3 months".
String aboutMonths(int n) => n == 1 ? 'about a month' : 'about $n months';

/// A goal's category icon in a well tinted per goal category (stable by
/// enum order); neutral when [dimmed] (completed or archived).
class GoalMark extends StatelessWidget {
  const GoalMark({super.key, required this.category, this.dimmed = false, this.size = 40});

  final GoalCategory category;
  final bool dimmed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = CategoryIcons.of(category.iconKey);
    if (dimmed) return IconWell(icon: icon, color: context.ink.inkSoft, size: size);
    final (fg, bg) = context.ink.tint(category.index % 14);
    return IconWell(icon: icon, color: fg, background: bg, size: size);
  }
}
