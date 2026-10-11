import 'dart:math';

/// Produces unique identifiers for new records.
///
/// The format (`prefix_<time36><rand36>`) sorts roughly by creation time and
/// is safe to send to a backend that later assigns its own canonical ids.
abstract interface class IdGenerator {
  String next(String prefix);
}

class RandomIdGenerator implements IdGenerator {
  RandomIdGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  @override
  String next(String prefix) {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = List.generate(6, (_) => _random.nextInt(36).toRadixString(36)).join();
    return '${prefix}_$time$rand';
  }
}

/// Deterministic generator for tests: `tx_1`, `tx_2`, …
class SequentialIdGenerator implements IdGenerator {
  final Map<String, int> _counters = {};

  @override
  String next(String prefix) {
    final n = (_counters[prefix] ?? 0) + 1;
    _counters[prefix] = n;
    return '${prefix}_$n';
  }
}
