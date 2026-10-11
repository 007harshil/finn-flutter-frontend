import 'dart:convert';

import 'package:finn/actions/action.dart';
import 'package:flutter_test/flutter_test.dart';

/// Straightforward 64-bit FNV-1a, exact on every platform via BigInt.
String _reference(String s) {
  final mask = (BigInt.one << 64) - BigInt.one;
  final prime = BigInt.parse('100000001b3', radix: 16);
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  for (final unit in utf8.encode(s)) {
    hash = ((hash ^ BigInt.from(unit)) * prime) & mask;
  }
  return hash.toRadixString(16);
}

void main() {
  test('matches published FNV-1a 64 vectors', () {
    expect(fnv1a64(''), 'cbf29ce484222325');
    expect(fnv1a64('a'), 'af63dc4c8601ec8c');
    expect(fnv1a64('foobar'), '85944171f73967e8');
  });

  test('matches BigInt reference on varied input', () {
    final inputs = [
      '{"action":"transactions.create","input":{"amount":125000,"note":"Chai ☕ और नाश्ता"}}',
      for (var i = 0; i < 300; i++) String.fromCharCodes(List.generate(i, (j) => 32 + (i * 31 + j * 17) % 95)),
    ];
    for (final s in inputs) {
      expect(fnv1a64(s), _reference(s), reason: s);
    }
  });
}
