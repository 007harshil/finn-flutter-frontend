import '../../core/money/money.dart';
import '../../features/categories/domain/category.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../finance/finance_snapshot.dart';
import '../prompt/agent_prompt.dart' show isSelectableCategory;

/// Deterministic helpers that turn the model's loose op fields into exact
/// values. Ordinary code does this more reliably than a model: amounts with
/// lakh/crore suffixes, relative dates in the user's time zone, record names
/// matched against the user's own data, and checks that optional details
/// were really said rather than invented.

/// A field value that cannot be used; [message] is safe to show.
class FieldProblem implements Exception {
  const FieldProblem(this.field, this.message);
  final String field;
  final String message;

  @override
  String toString() => 'FieldProblem($field: $message)';
}

abstract final class AgentAmount {
  static final _pattern = RegExp(
    r'^(?:₹|rs\.?|inr)?\s*([\d,]*\.?\d+)\s*(k|thousand|l|lakh|lakhs|lac|lacs|cr|crore|crores)?\s*(?:₹|rs\.?|rupees?|/-)?$',
    caseSensitive: false,
  );

  /// Rupees from a number or text such as `5000`, `"₹5,000"`, `"2k"`,
  /// `"1.5L"` or `"1 crore"`. Null when [v] is null; throws [FieldProblem]
  /// when it is not a positive amount with at most two decimals.
  static Money? parse(Object? v, {String field = 'amount'}) {
    if (v == null) return null;
    Money? m;
    if (v is num) {
      if (v.isFinite && v > 0) m = Money.tryParse(_decimal(v));
    } else if (v is String) {
      final match = _pattern.firstMatch(v.trim());
      if (match != null) {
        final n = num.tryParse(match.group(1)!.replaceAll(',', ''));
        final suffix = (match.group(2) ?? '').toLowerCase();
        final factor = switch (suffix) {
          'k' || 'thousand' => 1000,
          'l' || 'lakh' || 'lakhs' || 'lac' || 'lacs' => 100000,
          'cr' || 'crore' || 'crores' => 10000000,
          _ => 1,
        };
        if (n != null && n > 0) m = Money.tryParse(_decimal(n * factor));
      }
    }
    if (m == null || !m.isPositive) throw FieldProblem(field, 'The amount is not clear.');
    return m;
  }

  static String _decimal(num n) {
    final cents = (n * 100).round();
    return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
  }

  /// The only amount in a short reply such as "350", "₹350 only" or
  /// "it was 2.5k", or null when there is none or more than one.
  static Money? only(String text) {
    final matches = RegExp(
      r'(?:₹|rs\.?\s*)?\d[\d,]*(?:\.\d+)?\s*(?:k|l|lakh|lac|cr|crore)?\b',
      caseSensitive: false,
    ).allMatches(text).toList();
    if (matches.length != 1 || text.trim().split(RegExp(r'\s+')).length > 6) return null;
    try {
      return parse(matches.single.group(0)!.trim());
    } on FieldProblem {
      return null;
    }
  }
}

abstract final class AgentDate {
  /// A calendar date from a day offset (`-1`), a word (`"yesterday"`) or
  /// `yyyy-mm-dd`, relative to [today] (the user's time zone). Null when
  /// [v] is null; throws [FieldProblem] for anything else.
  static DateTime? resolve(Object? v, DateTime today, {String field = 'date'}) {
    if (v == null) return null;
    final base = DateTime(today.year, today.month, today.day);
    DateTime offset(int days) => DateTime(base.year, base.month, base.day + days);
    if (v is num && v == v.roundToDouble() && v.abs() <= 3660) return offset(v.toInt());
    if (v is String) {
      final s = v.trim().toLowerCase();
      final n = int.tryParse(s);
      if (n != null && n.abs() <= 3660) return offset(n);
      switch (s) {
        case 'today' || 'now':
          return base;
        case 'yesterday':
          return offset(-1);
        case 'day before yesterday':
          return offset(-2);
        case 'tomorrow':
          return offset(1);
      }
      final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
      if (m != null) {
        final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
        final date = DateTime(y, mo, d);
        if (date.month == mo && date.day == d) return date;
      }
    }
    throw FieldProblem(field, 'The date is not clear.');
  }
}

/// Words that name a payment method, for checking that the user said one.
const Map<PaymentMethod, List<String>> _methodWords = {
  PaymentMethod.upi: ['upi', 'gpay', 'google pay', 'phonepe', 'phone pe', 'paytm', 'bhim', 'qr'],
  PaymentMethod.card: ['card', 'credit', 'debit', 'visa', 'mastercard', 'rupay', 'amex'],
  PaymentMethod.cash: ['cash', 'nakad'],
  PaymentMethod.bankTransfer: ['bank', 'neft', 'imps', 'rtgs', 'transfer', 'cheque', 'check'],
  PaymentMethod.wallet: ['wallet', 'amazon pay', 'mobikwik'],
};

abstract final class AgentMethod {
  /// The payment method the model named, kept only when the user's text
  /// actually mentions a payment method (models tend to add one).
  static PaymentMethod? resolve(Object? v, String userText) {
    if (v is! String) return null;
    final key = v.trim().toLowerCase();
    final method = switch (key) {
      'upi' => PaymentMethod.upi,
      'card' => PaymentMethod.card,
      'cash' => PaymentMethod.cash,
      'bank' || 'banktransfer' || 'bank transfer' || 'neft' || 'imps' => PaymentMethod.bankTransfer,
      'wallet' => PaymentMethod.wallet,
      'other' => PaymentMethod.other,
      _ => null,
    };
    if (method == null || method == PaymentMethod.other) return null;
    final text = userText.toLowerCase();
    final mentioned = (_methodWords[method] ?? const []).any((w) => RegExp('\\b${RegExp.escape(w)}').hasMatch(text));
    return mentioned ? method : null;
  }
}

/// Lowercase word tokens without filler words.
List<String> nameTokens(String s) => [
  for (final t in s.toLowerCase().split(RegExp(r'[^a-z0-9ऀ-ॿ]+')))
    if (t.isNotEmpty && !_filler.contains(t)) t,
];

const _filler = {
  'my', 'the', 'a', 'an', 'for', 'of', 'to', 'and', 'in', 'on', 'at', 'with', 'from', 'by', 'our', 'mera', 'meri', 'one',
  'that', 'this', 'it', 'was', 'is', 'wala', 'vala',
};

/// Whether [value] (a shop or person the model extracted) appears in the
/// user's [text] or in [extra] app context, so it was not invented.
bool grounded(String value, String text, {String extra = ''}) {
  final hay = '${text.toLowerCase()} ${extra.toLowerCase()}';
  final tokens = nameTokens(value).where((t) => t.length >= 2);
  return tokens.isNotEmpty && tokens.any(hay.contains);
}

/// Outcome of matching a name against the user's records.
sealed class NameMatch<T> {
  const NameMatch();
}

final class Matched<T> extends NameMatch<T> {
  const Matched(this.value);
  final T value;
}

final class Ambiguous<T> extends NameMatch<T> {
  const Ambiguous(this.candidates);
  final List<T> candidates;
}

final class NoMatch<T> extends NameMatch<T> {
  const NoMatch();
}

/// Finds the record a name refers to, the way a person would: an exact
/// name first, then every word of the query contained in the record's
/// words ("Japan trip" → "Japan cherry blossom trip"), then the best partial
/// overlap. Several equally good candidates are never narrowed by guessing.
NameMatch<T> matchByName<T>(String query, Iterable<T> items, Iterable<String> Function(T) labels) {
  final list = items.toList();
  final q = query.trim().toLowerCase();
  if (q.isEmpty || list.isEmpty) return NoMatch<T>();
  final exact = [
    for (final it in list)
      if (labels(it).any((l) => l.trim().toLowerCase() == q)) it,
  ];
  if (exact.length == 1) return Matched(exact.single);
  if (exact.length > 1) return Ambiguous(exact);

  final qt = nameTokens(q);
  if (qt.isEmpty) return NoMatch<T>();
  double score(T it) {
    final words = labels(it).expand(nameTokens).toSet();
    bool hit(String t) => words.any((w) => w == t || (t.length >= 4 && (w.startsWith(t) || t.startsWith(w))));
    return qt.where(hit).length / qt.length;
  }

  final scored = [for (final it in list) (it, score(it))]..sort((a, b) => b.$2.compareTo(a.$2));
  final best = scored.first.$2;
  if (best < 0.5) return NoMatch<T>();
  final top = [for (final s in scored) if (s.$2 == best) s.$1];
  return top.length == 1 ? Matched(top.single) : Ambiguous(top);
}

/// Category by the name the model chose, among the user's selectable
/// categories of [type]. Null when nothing matches well.
TransactionCategory? findCategory(FinanceSnapshot s, String name, TransactionType type) {
  final options = s.categories.where((c) => isSelectableCategory(c) && c.type == type);
  final m = matchByName(name.replaceAll('&', ' '), options, (c) => [c.name, c.name.replaceAll('&', ' ')]);
  return m is Matched<TransactionCategory> ? m.value : null;
}

/// The general "other" category of [type] (always present).
TransactionCategory? otherCategory(FinanceSnapshot s, TransactionType type) => s.categories
    .where((c) => c.id.endsWith(type == TransactionType.income ? '_other_in' : '_other_out') && !c.isArchived)
    .firstOrNull;
