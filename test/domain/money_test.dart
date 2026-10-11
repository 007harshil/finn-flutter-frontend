import 'dart:math';

import 'package:finn/core/money/money.dart';
import 'package:finn/core/money/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

Money p(int paise) => Money.fromPaise(paise);

void main() {
  group('Money.tryParse', () {
    test('accepts Indian grouping, rupee symbol, spaces and up to two decimals', () {
      expect(Money.tryParse('1,25,000'), p(12500000));
      expect(Money.tryParse('₹1,00,00,000'), p(1000000000));
      expect(Money.tryParse('₹ 499.5'), p(49950));
      expect(Money.tryParse('12000.75'), p(1200075));
      expect(Money.tryParse('  42 '), p(4200));
      expect(Money.tryParse('0.05'), p(5));
      expect(Money.tryParse('.5'), p(50));
      expect(Money.tryParse('7.'), p(700));
      expect(Money.tryParse('0'), Money.zero);
    });

    test('rejects more than two decimals', () {
      expect(Money.tryParse('1.234'), isNull);
      expect(Money.tryParse('0.001'), isNull);
      expect(Money.tryParse('₹1,250.505'), isNull);
    });

    test('rejects negatives and malformed input', () {
      expect(Money.tryParse('-5'), isNull);
      expect(Money.tryParse('-0.50'), isNull);
      expect(Money.tryParse('₹-100'), isNull);
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('   '), isNull);
      expect(Money.tryParse('.'), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1e5'), isNull);
      expect(Money.tryParse('1.2.3'), isNull);
      expect(Money.tryParse('12a'), isNull);
    });

    test('decimal string round trip including negatives', () {
      for (final v in [0, 1, 5, 99, 100, 12345, -12345, -5, 1000000000, -1205]) {
        final m = p(v);
        expect(Money.fromDecimalString(m.toDecimalString()), m, reason: m.toDecimalString());
      }
      expect(p(-1205).toDecimalString(), '-12.05');
      expect(p(12500050).toDecimalString(), '125000.50');
      expect(() => Money.fromDecimalString('1.234'), throwsFormatException);
    });
  });

  group('Money arithmetic', () {
    test('operators are exact in paise', () {
      expect(p(10) + p(20), p(30));
      expect(p(10) - p(25), p(-15));
      expect(-p(10), p(-10));
      expect(p(333).times(3), p(999));
      expect(const Money.rupees(5), p(500));
      expect(Money.sum([p(1), p(2), p(3)]), p(6));
      expect(<Money>[].sum(), Money.zero);
      expect(Money.max(p(1), p(2)), p(2));
      expect(Money.min(p(1), p(2)), p(1));
      expect(p(-7).abs(), p(7));
      expect(p(1) < p(2) && p(2) <= p(2) && p(3) > p(2) && p(2) >= p(2), isTrue);
      expect(p(5).compareTo(p(4)), 1);
    });

    test('rupee and paise parts', () {
      expect(p(12345).rupeePart, 123);
      expect(p(12345).paisePart, 45);
      expect(p(-12345).rupeePart, -123);
      expect(p(-12345).paisePart, 45);
      expect(p(12300).hasPaise, isFalse);
      expect(p(12301).hasPaise, isTrue);
      expect(p(0).isZero && p(1).isPositive && p(-1).isNegative, isTrue);
    });

    test('equality and hashing by paise', () {
      expect(p(100) == const Money.rupees(1), isTrue);
      expect({p(100), const Money.rupees(1)}.length, 1);
    });
  });

  group('roundDiv', () {
    test('down truncates toward zero', () {
      expect(roundDiv(5, 3, RoundingMode.down), 1);
      expect(roundDiv(-5, 3, RoundingMode.down), -1);
      expect(roundDiv(9, 10, RoundingMode.down), 0);
    });

    test('up rounds away from zero', () {
      expect(roundDiv(1, 3, RoundingMode.up), 1);
      expect(roundDiv(-1, 3, RoundingMode.up), -1);
      expect(roundDiv(6, 3, RoundingMode.up), 2);
    });

    test('halfUp rounds ties away from zero', () {
      expect(roundDiv(4, 10, RoundingMode.halfUp), 0);
      expect(roundDiv(5, 10, RoundingMode.halfUp), 1);
      expect(roundDiv(7, 2, RoundingMode.halfUp), 4);
      expect(roundDiv(-7, 2, RoundingMode.halfUp), -4);
      expect(roundDiv(-5, 10, RoundingMode.halfUp), -1);
      expect(roundDiv(-4, 10, RoundingMode.halfUp), 0);
    });

    test('halfEven rounds ties to the even neighbour (also for negatives)', () {
      expect(roundDiv(5, 10, RoundingMode.halfEven), 0);
      expect(roundDiv(15, 10, RoundingMode.halfEven), 2);
      expect(roundDiv(25, 10, RoundingMode.halfEven), 2);
      expect(roundDiv(35, 10, RoundingMode.halfEven), 4);
      expect(roundDiv(5, 2, RoundingMode.halfEven), 2);
      expect(roundDiv(7, 2, RoundingMode.halfEven), 4);
      expect(roundDiv(-5, 2, RoundingMode.halfEven), -2);
      expect(roundDiv(-7, 2, RoundingMode.halfEven), -4);
      expect(roundDiv(-25, 10, RoundingMode.halfEven), -2);
      // Not a tie: behaves like ordinary rounding.
      expect(roundDiv(26, 10, RoundingMode.halfEven), 3);
      expect(roundDiv(24, 10, RoundingMode.halfEven), 2);
      expect(roundDiv(-26, 10, RoundingMode.halfEven), -3);
    });

    test('exact division ignores the mode', () {
      for (final mode in RoundingMode.values) {
        expect(roundDiv(12, 4, mode), 3);
        expect(roundDiv(-12, 4, mode), -3);
        expect(roundDiv(0, 7, mode), 0);
      }
    });

    test('BigInt variant agrees with the int variant', () {
      final r = Random(42);
      for (var i = 0; i < 2000; i++) {
        final n = r.nextInt(200000) - 100000;
        final d = r.nextInt(999) + 1;
        for (final mode in RoundingMode.values) {
          expect(roundDivBig(BigInt.from(n), BigInt.from(d), mode).toInt(), roundDiv(n, d, mode),
              reason: '$n / $d $mode');
        }
      }
    });
  });

  group('scale, ratio, allocation', () {
    test('scale multiplies by a fraction with explicit rounding', () {
      expect(p(1000).scale(1, 3), p(333));
      expect(p(1000).scale(2, 3), p(667));
      expect(p(1000).scale(1, 3, mode: RoundingMode.up), p(334));
      expect(p(1000).scale(2, 3, mode: RoundingMode.down), p(666));
      expect(p(-1000).scale(1, 3), p(-333));
      expect(p(-1000).scale(2, 3), p(-667));
      expect(p(25).scale(1, 10, mode: RoundingMode.halfEven), p(2));
      expect(p(35).scale(1, 10, mode: RoundingMode.halfEven), p(4));
      // Large values do not overflow (BigInt intermediate).
      expect(p(900000000000000).scale(52, 12), p(3900000000000000));
    });

    test('roundToRupee', () {
      expect(p(12350).roundToRupee(), p(12400));
      expect(p(12349).roundToRupee(), p(12300));
      expect(p(12301).roundToRupee(mode: RoundingMode.up), p(12400));
      expect(p(12399).roundToRupee(mode: RoundingMode.down), p(12300));
      expect(p(-12350).roundToRupee(), p(-12400));
    });

    test('ratioBps in basis points, half-up, null for zero whole', () {
      expect(p(25).ratioBps(p(100)), 2500);
      expect(p(1).ratioBps(p(3)), 3333);
      expect(p(2).ratioBps(p(3)), 6667);
      expect(p(150).ratioBps(p(100)), 15000);
      expect(p(-25).ratioBps(p(100)), -2500);
      expect(p(25).ratioBps(p(-100)), -2500);
      expect(p(-25).ratioBps(p(-100)), 2500);
      expect(p(10).ratioBps(Money.zero), isNull);
      expect(Money.zero.ratioBps(p(100)), 0);
    });

    test('allocateEvenly never creates or loses a paisa', () {
      expect(p(100).allocateEvenly(3), [p(34), p(33), p(33)]);
      expect(p(-100).allocateEvenly(3), [p(-34), p(-33), p(-33)]);
      expect(p(5).allocateEvenly(7).where((m) => m == p(1)).length, 5);
      expect(p(0).allocateEvenly(4), List.filled(4, Money.zero));
      final r = Random(1);
      for (var i = 0; i < 1000; i++) {
        final total = r.nextInt(10000000) - 5000000;
        final parts = r.nextInt(30) + 1;
        final shares = p(total).allocateEvenly(parts);
        expect(shares.length, parts);
        expect(Money.sum(shares), p(total), reason: '$total / $parts');
        final values = shares.map((m) => m.paise).toList();
        expect(values.reduce(max) - values.reduce(min), lessThanOrEqualTo(1));
      }
    });
  });

  group('MoneyFormatter', () {
    test('Indian digit grouping', () {
      expect(MoneyFormatter.groupIndian(0), '0');
      expect(MoneyFormatter.groupIndian(999), '999');
      expect(MoneyFormatter.groupIndian(1000), '1,000');
      expect(MoneyFormatter.groupIndian(99999), '99,999');
      expect(MoneyFormatter.groupIndian(100000), '1,00,000');
      expect(MoneyFormatter.groupIndian(1234567), '12,34,567');
      expect(MoneyFormatter.groupIndian(10000000), '1,00,00,000');
      expect(MoneyFormatter.groupIndian(123456789012), '1,23,45,67,89,012');
    });

    test('whole rupees', () {
      expect(const Money.rupees(125000).format(), '₹1,25,000');
      expect(const Money.rupees(10000000).format(), '₹1,00,00,000');
      expect(const Money.rupees(999).format(), '₹999');
      expect(Money.zero.format(), '₹0');
    });

    test('paise display modes', () {
      expect(p(12345).format(), '₹123.45');
      expect(p(12305).format(), '₹123.05');
      expect(p(12300).format(), '₹123');
      expect(p(10000).format(decimals: DecimalDisplay.always), '₹100.00');
      expect(p(12345678).format(decimals: DecimalDisplay.always), '₹1,23,456.78');
      // `none` rounds half-up to whole rupees.
      expect(p(12350).format(decimals: DecimalDisplay.none), '₹124');
      expect(p(12349).format(decimals: DecimalDisplay.none), '₹123');
      expect(p(-12350).format(decimals: DecimalDisplay.none), '−₹124');
      expect(p(12350).whole, '₹124');
    });

    test('sign modes use a true minus sign', () {
      expect(const Money.rupees(-500).format(), '−₹500');
      expect(const Money.rupees(500).format(sign: SignDisplay.always), '+₹500');
      expect(const Money.rupees(-500).format(sign: SignDisplay.always), '−₹500');
      expect(Money.zero.format(sign: SignDisplay.always), '₹0');
      expect(const Money.rupees(-500).format(sign: SignDisplay.never), '₹500');
      expect(MoneyFormatter.format(const Money.rupees(1500), withSymbol: false), '1,500');
    });

    test('compact L / Cr / K notation', () {
      expect(const Money.rupees(950).compact, '₹950');
      expect(const Money.rupees(1000).compact, '₹1K');
      expect(const Money.rupees(12500).compact, '₹12.5K');
      expect(const Money.rupees(100000).compact, '₹1L');
      expect(const Money.rupees(325000).compact, '₹3.25L');
      expect(const Money.rupees(1250000).compact, '₹12.5L');
      expect(const Money.rupees(10000000).compact, '₹1Cr');
      expect(const Money.rupees(12000000).compact, '₹1.2Cr');
      expect(const Money.rupees(1500000000).compact, '₹150Cr');
      expect(const Money.rupees(-325000).compact, '−₹3.25L');
      expect(MoneyFormatter.compact(const Money.rupees(325000), withSymbol: false), '3.25L');
    });

    test('editable, spoken and percentage helpers', () {
      expect(MoneyFormatter.editable(p(150000)), '1500');
      expect(MoneyFormatter.editable(p(150050)), '1500.50');
      expect(Money.tryParse(MoneyFormatter.editable(p(150050))), p(150050));
      expect(MoneyFormatter.spoken(p(12500050)), '1,25,000 rupees 50 paise');
      expect(MoneyFormatter.spoken(p(-10000)), 'minus 100 rupees');
      expect(formatBps(1850), '18.5%');
      expect(formatBps(1800), '18%');
      expect(formatBps(7560, decimals: 0), '76%');
    });
  });
}
