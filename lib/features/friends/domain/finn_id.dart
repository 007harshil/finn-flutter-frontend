/// FiNN IDs: 8 characters from [alphabet] (no 0, 1, I, O). Stored uppercase
/// without a dash (`K7Q2M9XD`), shown as `K7Q2-M9XD`.
abstract final class FinnId {
  static const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const length = 8;

  static final _valid = RegExp(r'^[2-9A-HJ-NP-Z]{8}$');

  /// Shown when the input is not a FiNN ID.
  static const invalidMessage = 'Enter a valid FiNN ID, like K7Q2-M9XD.';

  /// The stored form of [input] (spaces and dashes dropped, uppercased), or
  /// null when it is not a valid FiNN ID.
  static String? normalize(String input) {
    final id = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    return _valid.hasMatch(id) ? id : null;
  }

  static bool isValid(String input) => normalize(input) != null;

  /// `K7Q2M9XD` becomes `K7Q2-M9XD`. Anything that is not 8 characters is
  /// returned unchanged.
  static String format(String id) =>
      id.length == length ? '${id.substring(0, 4)}-${id.substring(4)}' : id;
}
