import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../kit/kit.dart';
import '../../../accounts/domain/money_account.dart';
import '../../../accounts/presentation/widgets/account_ui.dart';

/// Where the money is, inside the hero slab: a header ("Accounts 2" and
/// Manage) over one tile per active account (icon, name, kind and last 4,
/// balance; credit cards show what is owed). Two accounts share the width;
/// more scroll sideways, with the next tile peeking in. Hidden until
/// accounts load.
///
/// Drawn for the deep slab, so its colours are fixed in light and dark.
class HeroAccountsStrip extends ConsumerWidget {
  const HeroAccountsStrip({super.key, required this.inset});

  /// Horizontal padding of the slab. The scroller runs edge to edge and
  /// uses this as its own padding, so tiles slide out under the slab's edge.
  final double inset;

  static const _tileWidth = 140.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(accountBalancesProvider).value;
    if (all == null) return const SizedBox.shrink();
    final active = [
      for (final b in all)
        if (!b.account.isArchived) b,
    ];
    if (active.isEmpty) return const SizedBox.shrink();
    final t = context.type;

    final Widget tiles;
    if (active.length <= 2) {
      tiles = Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < active.length; i++) ...[
                if (i > 0) const SizedBox(width: Sp.sm + 2),
                Expanded(child: _AccountTile(balance: active[i])),
              ],
            ],
          ),
        ),
      );
    } else {
      tiles = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: inset),
        physics: const BouncingScrollPhysics(),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < active.length; i++) ...[
                if (i > 0) const SizedBox(width: Sp.sm + 2),
                SizedBox(
                  width: _tileWidth,
                  child: _AccountTile(balance: active[i]),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Container(height: 1, color: _Tile.line),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(inset, Sp.xs, inset - Sp.sm, Sp.xs),
            child: Row(
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Accounts'),
                          TextSpan(
                            text: '  ${active.length}',
                            style: t.label.copyWith(color: _Tile.soft),
                          ),
                        ],
                      ),
                      style: t.labelStrong.copyWith(color: _Tile.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const Spacer(),
                _ManageLink(onTap: () => context.push(AppRoutes.accounts)),
              ],
            ),
          ),
          tiles,
        ],
      ),
    );
  }
}

/// "Manage ›" on the slab; a 44pt tall target.
class _ManageLink extends StatelessWidget {
  const _ManageLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Semantics(
      button: true,
      label: 'Manage accounts',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: Rad.rSm,
          splashColor: Colors.white.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Manage', style: t.labelStrong.copyWith(color: _Tile.ink)),
                  const SizedBox(width: 2),
                  const Icon(LucideIcons.chevronRight, size: 16, color: _Tile.soft),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One account on the slab: icon and name, kind and last 4, balance (owed
/// on credit cards), and what is set aside on it. Opens the account.
class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.balance});

  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final a = balance.account;
    final hidden = AmountVisibility.hiddenOf(context);
    final m = balance.balance;
    final owes = balance.isLiability && m.isPositive;
    final negative = !balance.isLiability && m.isNegative;
    final over = !balance.isLiability && balance.available.isNegative;
    String money(Money m) => hidden ? MoneyFormatter.masked : MoneyFormatter.format(m, decimals: DecimalDisplay.none);

    final String? note = balance.isLiability
        ? limitLeftText(balance, short: true)
        : SetAsideLine.shows(balance)
        ? (over ? 'Over-reserved ${money(-balance.available)}' : '${money(balance.earmarked)} set aside')
        : null;

    return Semantics(
      button: true,
      label: accountSemantics(balance, hidden: hidden),
      excludeSemantics: true,
      child: Material(
        key: ValueKey('account-row-${a.id}'),
        color: _Tile.fill,
        shape: const RoundedRectangleBorder(
          borderRadius: Rad.rMd,
          side: BorderSide(color: _Tile.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          splashColor: Colors.white.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          onTap: () {
            HapticFeedback.selectionClick();
            context.push(AppRoutes.accountDetail(a.id));
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.md - 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(color: _Tile.well, shape: BoxShape.circle),
                      child: Icon(accountIcon(a.kind), size: 14, color: _Tile.ink),
                    ),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: Text(
                        a.name,
                        style: t.labelStrong.copyWith(color: _Tile.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Sp.sm + 2),
                AmountText(
                  m,
                  style: t.figure.copyWith(fontSize: 17, color: owes || negative ? _Tile.over : _Tile.ink),
                  decimals: DecimalDisplay.none,
                  fit: true,
                ),
                const SizedBox(height: 2),
                Text(
                  [if (owes) 'owed', accountSubtitle(a), if (a.isDefault) 'Default'].join(' · '),
                  style: t.small.copyWith(color: _Tile.soft),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: t.small.copyWith(color: over ? _Tile.over : _Tile.soft),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fills and text on the deep slab (the same in light and dark mode).
abstract final class _Tile {
  static const ink = Color(0xFFFFFFFF);
  static const soft = Color(0xD9FFFFFF);
  static const fill = Color(0x14FFFFFF);
  static const well = Color(0x1FFFFFFF);
  static const line = Color(0x1FFFFFFF);
  static const over = Color(0xFFFFA494);
}
