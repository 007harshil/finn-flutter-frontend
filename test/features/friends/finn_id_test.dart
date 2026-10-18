import 'package:finn/data/mock/finn_users.dart';
import 'package:finn/features/friends/domain/finn_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FinnId.normalize', () {
    test('accepts the stored and the shown form', () {
      expect(FinnId.normalize('K7Q2M9XD'), 'K7Q2M9XD');
      expect(FinnId.normalize('K7Q2-M9XD'), 'K7Q2M9XD');
    });

    test('drops spaces and dashes and uppercases', () {
      expect(FinnId.normalize('  k7q2 - m9xd '), 'K7Q2M9XD');
      expect(FinnId.normalize('k7-q2-m9-xd'), 'K7Q2M9XD');
    });

    test('rejects wrong length', () {
      expect(FinnId.normalize(''), isNull);
      expect(FinnId.normalize('K7Q2M9X'), isNull);
      expect(FinnId.normalize('K7Q2M9XDA'), isNull);
    });

    test(
      'rejects the characters the alphabet leaves out (0, 1, I, O) and symbols',
      () {
        for (final bad in [
          'K7Q2M9X0',
          'K7Q2M9X1',
          'K7Q2M9XI',
          'K7Q2M9XO',
          'K7Q2M9X!',
          'K7Q2_M9XD',
        ]) {
          expect(FinnId.normalize(bad), isNull, reason: bad);
        }
      },
    );

    test('every alphabet character is valid', () {
      expect(FinnId.alphabet.length, 32);
      for (final ch in FinnId.alphabet.split('')) {
        expect(FinnId.isValid(ch * 8), isTrue, reason: ch);
      }
    });
  });

  test('format shows a dash in the middle', () {
    expect(FinnId.format('K7Q2M9XD'), 'K7Q2-M9XD');
    expect(FinnId.format('short'), 'short');
  });

  test('mock users have valid, unique FiNN IDs', () {
    final ids = [for (final u in mockFinnUsers) u.finnId!, mockMyFinnId];
    expect(ids.every(FinnId.isValid), isTrue);
    expect(ids.toSet().length, ids.length);
  });
}
