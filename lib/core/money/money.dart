import 'package:flutter/foundation.dart';

/// Rounding modes used by every authoritative money calculation in FiNN.
///
/// FiNN never rounds implicitly: each calculation that can produce a
/// fractional paisa states which mode it applies. See
/// `docs/FINANCIAL_MODEL.md` for the policy per calculation.
enum RoundingMode {
  /// Round half away from zero (commercial rounding). Default policy.
  halfUp,

  /// Banker's rounding. Used for aggregate statistics only.
  halfEven,

  /// Truncate toward zero.
  down,

  /// Away from zero (ceiling for positive values).
  up,
}

/// Integer division of [numerator] by [denominator] using [mode].
///
/// Works for negative numerators; [denominator] must be positive.
int roundDiv(int numerator, int denominator, RoundingMode mode) {
  assert(denominator > 0, 'denominator must be positive');
  final negative = numerator < 0;
  final n = numerator.abs();
  final q = n ~/ denominator;
  final r = n % denominator;
  int result;
  if (r == 0) {
    result = q;
  } else {
    switch (mode) {
      case RoundingMode.down:
        result = q;
      case RoundingMode.up:
        result = q + 1;
      case RoundingMode.halfUp:
        result = (r * 2 >= denominator) ? q + 1 : q;
      case RoundingMode.halfEven:
        final twice = r * 2;
        if (twice > denominator) {
          result = q + 1;
        } else if (twice < denominator) {
          result = q;
        } else {
          result = q.isEven ? q : q + 1;
        }
    }
  }
  return negative ? -result : result;
}

/// BigInt variant of [roundDiv] for calculations that can overflow 64 bits
/// (for example compound-interest factors in the EMI formula).
BigInt roundDivBig(BigInt numerator, BigInt denominator, RoundingMode mode) {
  assert(denominator > BigInt.zero, 'denominator must be positive');
  final negative = numerator.isNegative;
  final n = numerator.abs();
  final q = n ~/ denominator;
  final r = n.remainder(denominator);
  BigInt result;
  if (r == BigInt.zero) {
    result = q;
  } else {
    switch (mode) {
      case RoundingMode.down:
        result = q;
      case RoundingMode.up:
        result = q + BigInt.one;
      case RoundingMode.halfUp:
        result = (r * BigInt.two >= denominator) ? q + BigInt.one : q;
      case RoundingMode.halfEven:
        final twice = r * BigInt.two;
        if (twice > denominator) {
          result = q + BigInt.one;
        } else if (twice < denominator) {
          result = q;
        } else {
          result = q.isEven ? q : q + BigInt.one;
        }
    }
  }
  return negative ? -result : result;
}

/// An exact amount of Indian rupees, stored as an integer number of paise.
///
/// Binary floating point is never used for authoritative values. [toDouble]
/// exists only for chart rendering and similar presentation needs.
@immutable
class Money implements Comparable<Money> {
  const Money.fromPaise(this.paise);

  /// Whole rupees.
  const Money.rupees(int rupees) : paise = rupees * 100;

  static const Money zero = Money.fromPaise(0);

  final int paise;

  /// Parses user input such as `1,25,000`, `₹ 499.5` or `12000.75`.
  ///
  /// Returns null for empty, malformed, or more-than-two-decimal input.
  /// Negative values are rejected; direction is always modelled explicitly.
  static Money? tryParse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[₹,\s]'), '');
    if (cleaned.isEmpty) return null;
    final match = RegExp(r'^(\d{0,13})(?:\.(\d{0,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final whole = match.group(1) ?? '';
    final frac = match.group(2) ?? '';
    if (whole.isEmpty && frac.isEmpty) return null;
    final rupees = whole.isEmpty ? 0 : int.parse(whole);
    final fracPaise = frac.isEmpty ? 0 : int.parse(frac.padRight(2, '0'));
    return Money.fromPaise(rupees * 100 + fracPaise);
  }

  /// Sum of [values]; zero for an empty iterable.
  static Money sum(Iterable<Money> values) {
    var total = 0;
    for (final v in values) {
      total += v.paise;
    }
    return Money.fromPaise(total);
  }

  static Money max(Money a, Money b) => a >= b ? a : b;
  static Money min(Money a, Money b) => a <= b ? a : b;

  bool get isZero => paise == 0;
  bool get isPositive => paise > 0;
  bool get isNegative => paise < 0;

  /// Whole rupee part (truncated toward zero).
  int get rupeePart => paise ~/ 100;

  /// Remaining paise (0..99), sign-less.
  int get paisePart => paise.abs() % 100;

  bool get hasPaise => paisePart != 0;

  Money abs() => Money.fromPaise(paise.abs());

  Money operator +(Money other) => Money.fromPaise(paise + other.paise);
  Money operator -(Money other) => Money.fromPaise(paise - other.paise);
  Money operator -() => Money.fromPaise(-paise);

  bool operator <(Money other) => paise < other.paise;
  bool operator <=(Money other) => paise <= other.paise;
  bool operator >(Money other) => paise > other.paise;
  bool operator >=(Money other) => paise >= other.paise;

  /// Multiplies by an integer factor (exact).
  Money times(int factor) => Money.fromPaise(paise * factor);

  /// Multiplies by `numerator / denominator` with explicit rounding.
  Money scale(
    int numerator,
    int denominator, {
    RoundingMode mode = RoundingMode.halfUp,
  }) {
    final big = roundDivBig(
      BigInt.from(paise) * BigInt.from(numerator),
      BigInt.from(denominator),
      mode,
    );
    return Money.fromPaise(big.toInt());
  }

  /// Rounds to whole rupees.
  Money roundToRupee({RoundingMode mode = RoundingMode.halfUp}) =>
      Money.fromPaise(roundDiv(paise, 100, mode) * 100);

  /// Ratio of this amount to [whole] in basis points (1/100 of a percent),
  /// rounded half-up. Returns null when [whole] is zero (ratio unknown).
  int? ratioBps(Money whole) {
    if (whole.paise == 0) return null;
    final sign = (paise < 0) != (whole.paise < 0) ? -1 : 1;
    final v = roundDivBig(
      BigInt.from(paise.abs()) * BigInt.from(10000),
      BigInt.from(whole.paise.abs()),
      RoundingMode.halfUp,
    ).toInt();
    return sign * v;
  }

  /// Splits into [parts] amounts that sum exactly to this amount. Remainder
  /// paise go to the first parts, so no paisa is ever created or lost.
  List<Money> allocateEvenly(int parts) {
    assert(parts > 0, 'parts must be positive');
    final base = paise ~/ parts;
    var remainder = paise - base * parts;
    final step = remainder >= 0 ? 1 : -1;
    return List<Money>.generate(parts, (_) {
      var share = base;
      if (remainder != 0) {
        share += step;
        remainder -= step;
      }
      return Money.fromPaise(share);
    });
  }

  /// Presentation only. Never use the result for authoritative arithmetic.
  double toDouble() => paise / 100.0;

  /// Machine-readable decimal string, e.g. `125000.50` or `-12.05`.
  String toDecimalString() {
    final sign = paise < 0 ? '-' : '';
    final p = paise.abs();
    return '$sign${p ~/ 100}.${(p % 100).toString().padLeft(2, '0')}';
  }

  /// Parses [toDecimalString] output (and plain numbers) for persistence.
  static Money fromDecimalString(String value) {
    final negative = value.startsWith('-');
    final parsed = tryParse(negative ? value.substring(1) : value);
    if (parsed == null) {
      throw FormatException('Invalid money value', value);
    }
    return negative ? -parsed : parsed;
  }

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;

  @override
  String toString() => 'Money(${toDecimalString()})';
}

extension MoneyIterableX on Iterable<Money> {
  Money sum() => Money.sum(this);
}
