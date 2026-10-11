import 'money.dart';

/// How a sign is rendered in front of an amount.
enum SignDisplay {
  /// Only negative amounts show a sign.
  auto,

  /// Positive amounts show `+`, negative `−`.
  always,

  /// No sign is ever rendered (direction is conveyed elsewhere).
  never,
}

/// How many decimals to render.
enum DecimalDisplay {
  /// Show paise only when the amount has a fractional part.
  auto,

  /// Always round to whole rupees for display.
  none,

  /// Always show two decimals.
  always,
}

/// Indian-locale (en-IN) money formatting: `₹1,25,000`, `₹3.2L`, `₹1.05Cr`.
///
/// Implemented without `NumberFormat` so it is deterministic across
/// platforms and cheap enough to call while building list rows.
class MoneyFormatter {
  const MoneyFormatter._();

  static const String symbol = '₹';
  static const String minus = '−';

  /// Groups an unsigned integer string using the Indian system (3,2,2…).
  static String groupIndian(int value) {
    final digits = value.abs().toString();
    if (digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }

  static String format(
    Money money, {
    SignDisplay sign = SignDisplay.auto,
    DecimalDisplay decimals = DecimalDisplay.auto,
    bool withSymbol = true,
  }) {
    final negative = money.isNegative;
    var p = money.paise.abs();
    String body;
    final showDecimals = switch (decimals) {
      DecimalDisplay.always => true,
      DecimalDisplay.none => false,
      DecimalDisplay.auto => p % 100 != 0,
    };
    if (showDecimals) {
      body = '${groupIndian(p ~/ 100)}.${(p % 100).toString().padLeft(2, '0')}';
    } else {
      p = roundDiv(p, 100, RoundingMode.halfUp);
      body = groupIndian(p);
    }
    final prefix = switch (sign) {
      SignDisplay.never => '',
      SignDisplay.auto => negative ? minus : '',
      SignDisplay.always => negative ? minus : (money.isZero ? '' : '+'),
    };
    return '$prefix${withSymbol ? symbol : ''}$body';
  }

  /// Compact Indian notation for tight spaces and chart axes:
  /// `₹950`, `₹12.5K`, `₹3.25L`, `₹1.2Cr`.
  static String compact(Money money, {bool withSymbol = true}) {
    final negative = money.isNegative;
    final rupees = money.paise.abs() / 100.0;
    String body;
    if (rupees >= 1e7) {
      body = '${_trim(rupees / 1e7)}Cr';
    } else if (rupees >= 1e5) {
      body = '${_trim(rupees / 1e5)}L';
    } else if (rupees >= 1e3) {
      body = '${_trim(rupees / 1e3)}K';
    } else {
      body = rupees.round().toString();
    }
    return '${negative ? minus : ''}${withSymbol ? symbol : ''}$body';
  }

  static String _trim(double v) {
    final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(v >= 10 ? 1 : 2);
    if (!s.contains('.')) return s;
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Plain editable representation used to pre-fill input fields.
  static String editable(Money money) {
    final p = money.paise.abs();
    if (p % 100 == 0) return (p ~/ 100).toString();
    return '${p ~/ 100}.${(p % 100).toString().padLeft(2, '0')}';
  }

  /// Masked value used when the user enables "Hide balances".
  static const String masked = '₹ ••••';

  /// Screen-reader friendly phrase, e.g. "minus 1,25,000 rupees 50 paise".
  static String spoken(Money money) {
    final negative = money.isNegative;
    final p = money.paise.abs();
    final rupees = groupIndian(p ~/ 100);
    final paise = p % 100;
    final buffer = StringBuffer();
    if (negative) buffer.write('minus ');
    buffer.write('$rupees rupees');
    if (paise != 0) buffer.write(' $paise paise');
    return buffer.toString();
  }
}

extension MoneyFormatX on Money {
  String format({
    SignDisplay sign = SignDisplay.auto,
    DecimalDisplay decimals = DecimalDisplay.auto,
  }) =>
      MoneyFormatter.format(this, sign: sign, decimals: decimals);

  String get compact => MoneyFormatter.compact(this);
  String get whole => MoneyFormatter.format(this, decimals: DecimalDisplay.none);
}

/// Formats a basis-point value as a percentage string, e.g. 1850 → "18.5%".
String formatBps(int bps, {int decimals = 1}) {
  final value = bps / 100.0;
  final s = value.toStringAsFixed(decimals);
  return '${decimals > 0 ? s.replaceFirst(RegExp(r'\.0+$'), '') : s}%';
}
