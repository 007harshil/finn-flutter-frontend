import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';

import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../kit/kit.dart';
import '../../domain/money_account.dart';

/// Icon for an account kind.
IconData accountIcon(MoneyAccountKind kind) => switch (kind) {
  MoneyAccountKind.cash => LucideIcons.banknote,
  MoneyAccountKind.bank => LucideIcons.landmark,
  MoneyAccountKind.debitCard => LucideIcons.creditCard,
  MoneyAccountKind.creditCard => LucideIcons.creditCard,
  MoneyAccountKind.promoCard => LucideIcons.gift,
  MoneyAccountKind.otherCard => LucideIcons.creditCard,
};

/// "Debit card ····4821" (kind and last 4 when there is one).
String accountSubtitle(MoneyAccount a) => a.subtitle;

/// What a credit card still has available, e.g. "₹1,80,000 limit left".
String? limitLeftText(AccountBalance b, {bool short = false}) {
  final left = b.limitLeft;
  if (left == null) return null;
  final text = MoneyFormatter.format(left, decimals: DecimalDisplay.none);
  return left.isNegative
      ? 'over limit by ${MoneyFormatter.format(-left, decimals: DecimalDisplay.none)}'
      : (short ? '$text left' : '$text limit left');
}

/// The balance of an account as a figure: money in it, or the amount owed
/// on a credit card (in the out colour when something is owed).
class AccountAmount extends StatelessWidget {
  const AccountAmount(
    this.balance, {
    super.key,
    this.style,
    this.decimals = DecimalDisplay.auto,
  });

  final AccountBalance balance;
  final TextStyle? style;
  final DecimalDisplay decimals;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final base = style ?? context.type.figure;
    final Money m = balance.balance;
    final color = balance.isLiability
        ? (m.isPositive ? c.red : c.ink)
        : (m.isNegative ? c.red : c.ink);
    return AmountText(
      m,
      style: base.copyWith(color: color),
      decimals: decimals,
    );
  }
}

/// "Available ₹X · set aside ₹Y" (quiet second line under an account that has
/// savings set aside on it). Over-reserved accounts show the shortfall in the
/// out colour.
class SetAsideLine extends StatelessWidget {
  const SetAsideLine(this.balance, {super.key});

  final AccountBalance balance;

  /// Whether [b] has anything set aside to report.
  static bool shows(AccountBalance b) => !b.isLiability && b.earmarked.isPositive;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final style = context.type.label;
    final hidden = AmountVisibility.hiddenOf(context);
    String money(Money m) => hidden ? MoneyFormatter.masked : MoneyFormatter.format(m, decimals: DecimalDisplay.none);
    final over = balance.available.isNegative;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: over ? 'Over-reserved ${money(-balance.available)}' : 'Available ${money(balance.available)}',
            style: over ? style.copyWith(color: c.red) : null,
          ),
          TextSpan(text: ' · set aside ${money(balance.earmarked)}'),
        ],
      ),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Spoken description of an account line for screen readers.
String accountSemantics(AccountBalance b, {bool hidden = false}) {
  final a = b.account;
  final amount = hidden
      ? 'amount hidden'
      : b.isLiability
      ? '${MoneyFormatter.spoken(b.balance)} owed'
      : MoneyFormatter.spoken(b.balance);
  final reserved = SetAsideLine.shows(b)
      ? hidden
            ? ', some money set aside'
            : b.available.isNegative
            ? ', over-reserved by ${MoneyFormatter.spoken(-b.available)}, ${MoneyFormatter.spoken(b.earmarked)} set aside'
            : ', ${MoneyFormatter.spoken(b.available)} available, ${MoneyFormatter.spoken(b.earmarked)} set aside'
      : '';
  return '${a.name}, ${a.subtitle}${a.isDefault ? ', default' : ''}, $amount$reserved';
}

/// One account in a panel: icon, name, kind and last 4, balance. Credit
/// cards show what is owed and the limit left. Opens the account.
class AccountRow extends StatelessWidget {
  const AccountRow({super.key, required this.balance, this.onTap});

  final AccountBalance balance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final a = balance.account;
    final hidden = AmountVisibility.hiddenOf(context);
    return LedgerRow(
      key: ValueKey('account-row-${a.id}'),
      leading: IconWell(icon: accountIcon(a.kind), size: 36),
      title: a.name,
      subtitle: [accountSubtitle(a), ?limitLeftText(balance, short: true), if (a.isDefault) 'Default'].join(' · '),
      subtitleLines: 2,
      below: SetAsideLine.shows(balance) ? SetAsideLine(balance) : null,
      trailing: AccountAmount(balance),
      trailingSub: balance.isLiability
          ? Text('owed', style: t.small.copyWith(color: c.inkSoft))
          : null,
      chevron: true,
      semanticLabel: accountSemantics(balance, hidden: hidden),
      onTap: onTap ?? () => context.push(AppRoutes.accountDetail(a.id)),
    );
  }
}
