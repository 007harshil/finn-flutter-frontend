import 'package:flutter/material.dart';

import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../motion/motion.dart';
import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';

/// Provides the "hide balances" flag to every [AmountText] below it.
class AmountVisibility extends InheritedWidget {
  const AmountVisibility({super.key, required this.hidden, required super.child});

  /// When true, amounts render as [MoneyFormatter.masked].
  final bool hidden;

  /// Whether amounts are hidden for [context]. Defaults to false.
  static bool hiddenOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmountVisibility>()?.hidden ?? false;

  @override
  bool updateShouldNotify(AmountVisibility oldWidget) => oldWidget.hidden != hidden;
}

/// Formats [amount] in Indian notation with masking and a spoken label.
class AmountText extends StatelessWidget {
  const AmountText(
    this.amount, {
    super.key,
    this.style,
    this.sign = SignDisplay.auto,
    this.decimals = DecimalDisplay.auto,
    this.colorize = false,
    this.color,
    this.compact = false,
    this.fit = false,
    this.textAlign,
    this.semanticsLabel,
  });

  final Money amount;

  /// Defaults to `context.text.amountMedium`.
  final TextStyle? style;
  final SignDisplay sign;
  final DecimalDisplay decimals;

  /// Positive amounts use `colors.positive`, negative `colors.negative`.
  final bool colorize;

  /// Explicit colour; wins over [colorize].
  final Color? color;

  /// Use compact notation (`₹3.2L`).
  final bool compact;

  /// Scale down (never clip) when space is tight. Use for hero amounts.
  final bool fit;
  final TextAlign? textAlign;

  /// Overrides the spoken label (rarely needed).
  final String? semanticsLabel;

  /// Text for [amount] using the given display options.
  static String formatted(
    Money amount, {
    SignDisplay sign = SignDisplay.auto,
    DecimalDisplay decimals = DecimalDisplay.auto,
    bool compact = false,
  }) {
    if (!compact) return MoneyFormatter.format(amount, sign: sign, decimals: decimals);
    return switch (sign) {
      SignDisplay.never => MoneyFormatter.compact(amount.abs()),
      SignDisplay.always when amount.isPositive => '+${MoneyFormatter.compact(amount)}',
      _ => MoneyFormatter.compact(amount),
    };
  }

  /// Screen-reader phrase for [amount].
  static String spokenLabel(Money amount, {SignDisplay sign = SignDisplay.auto}) {
    if (sign == SignDisplay.never) return MoneyFormatter.spoken(amount.abs());
    final prefix = sign == SignDisplay.always && amount.isPositive ? 'plus ' : '';
    return '$prefix${MoneyFormatter.spoken(amount)}';
  }

  @override
  Widget build(BuildContext context) {
    final hidden = AmountVisibility.hiddenOf(context);
    final c = context.colors;
    Color? resolved = color;
    if (resolved == null && colorize && !hidden) {
      if (amount.isPositive) resolved = c.positive;
      if (amount.isNegative) resolved = c.negative;
    }
    final base = style ?? context.text.amountMedium;
    final effective = resolved == null ? base : base.copyWith(color: resolved);
    final text = hidden
        ? MoneyFormatter.masked
        : formatted(amount, sign: sign, decimals: decimals, compact: compact);
    final label = hidden ? 'Amount hidden' : (semanticsLabel ?? spokenLabel(amount, sign: sign));

    Widget child = Text(
      text,
      style: effective,
      maxLines: 1,
      softWrap: false,
      overflow: fit ? TextOverflow.visible : TextOverflow.ellipsis,
      textAlign: textAlign,
    );
    if (fit) {
      child = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: switch (textAlign) {
          TextAlign.center => Alignment.center,
          TextAlign.right || TextAlign.end => Alignment.centerRight,
          _ => Alignment.centerLeft,
        },
        child: child,
      );
    }
    return Semantics(label: label, excludeSemantics: true, child: child);
  }
}

/// [AmountText] that counts up/down to a new value when [amount] changes.
class AnimatedAmount extends StatefulWidget {
  const AnimatedAmount(
    this.amount, {
    super.key,
    this.style,
    this.sign = SignDisplay.auto,
    this.decimals = DecimalDisplay.auto,
    this.colorize = false,
    this.color,
    this.compact = false,
    this.fit = false,
    this.textAlign,
    this.animateOnMount = false,
  });

  final Money amount;
  final TextStyle? style;
  final SignDisplay sign;
  final DecimalDisplay decimals;
  final bool colorize;
  final Color? color;
  final bool compact;
  final bool fit;
  final TextAlign? textAlign;

  /// Count up from zero on first build.
  final bool animateOnMount;

  @override
  State<AnimatedAmount> createState() => _AnimatedAmountState();
}

class _AnimatedAmountState extends State<AnimatedAmount> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Durations2.counter, value: 1);
  late Money _from = widget.amount;
  late Money _to = widget.amount;
  bool _started = false;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = context.reduceMotion;
    _controller.duration = context.motion.counter;
    if (!_started) {
      _started = true;
      if (widget.animateOnMount && !_reduced && !widget.amount.isZero) {
        _from = Money.zero;
        _controller.forward(from: 0);
      }
    } else if (_reduced && _controller.isAnimating) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(AnimatedAmount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.amount != _to) {
      _from = _current;
      _to = widget.amount;
      if (_reduced) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  Money get _current {
    if (_controller.value >= 1) return _to;
    final t = Curves.easeOutCubic.transform(_controller.value);
    final paise = _from.paise + (_to.paise - _from.paise) * t;
    return Money.rupees((paise / 100).round());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = AmountText.spokenLabel(widget.amount, sign: widget.sign);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final done = _controller.value >= 1;
          return AmountText(
            done ? _to : _current,
            style: widget.style,
            sign: widget.sign,
            decimals: done ? widget.decimals : DecimalDisplay.none,
            colorize: widget.colorize,
            color: widget.color,
            compact: widget.compact,
            fit: widget.fit,
            textAlign: widget.textAlign,
            semanticsLabel: label,
          );
        },
      ),
    );
  }
}
