import '../../core/money/money_format.dart';
import '../../features/transactions/application/transaction_actions.dart' show TransactionInput;
import 'proposals.dart';

/// One short past-tense sentence for a saved action, e.g. "Salary of
/// ₹20,000 added as income." Built from the approved preview and input
/// (never from model text), so it states exactly what was saved.
String actionRecap(ActionRecord record) {
  final p = record.proposal;
  final preview = p.preview;
  String? line(String label) {
    for (final l in preview.lines) {
      if (l.label == label && l.value != '—') return l.value;
    }
    return null;
  }

  final input = p.input;
  if (p.descriptor.id == 'transactions.create' && input is TransactionInput) {
    final amount = input.amount.format();
    final category = line('Category');
    final party = input.counterparty?.trim();
    if (input.type.isIncome) {
      final from = party == null || party.isEmpty ? '' : ' from $party';
      return category == null ? '$amount$from added as income.' : '$category of $amount$from added as income.';
    }
    final to = party == null || party.isEmpty ? '' : ' at $party';
    return category == null ? '$amount$to added as an expense.' : '$amount on $category$to added as an expense.';
  }
  return '${_pastTense(preview.summary)}.';
}

/// Turns a preview summary ("Update Rent budget to ₹9,000", "Pay Rahul
/// ₹500") into what happened ("Rent budget updated to ₹9,000", "Paid Rahul
/// ₹500"). Summaries already in the past tense pass through unchanged.
String _pastTense(String summary) {
  final s = summary.trim();
  String? rest(String prefix) => s.startsWith(prefix) ? s.substring(prefix.length) : null;

  if (rest('Update ') case final r?) {
    final to = r.indexOf(' to ');
    return to < 0 ? '$r updated' : '${r.substring(0, to)} updated to ${r.substring(to + 4)}';
  }
  if (rest('Delete the ') case final r?) return '$r deleted';
  if (rest('Delete ') case final r?) return '$r deleted';
  if (rest('Archive ') case final r?) return '$r archived';
  if (rest('Restore ') case final r?) return '$r restored';
  if (rest('Write off ') case final r?) return 'Wrote off $r';
  if (rest('Pay ') case final r?) return 'Paid $r';
  if (rest('Receive ') case final r?) return 'Received $r';
  if (rest('Owe ') case final r?) return 'Noted that you owe $r';
  if (rest('Collect ') case final r?) return 'Noted $r to collect';
  if (rest('New goal: ') case final r?) return 'Goal $r created';
  if (rest('Budget for ') case final r?) return 'Budget for $r created';
  if (rest('Emergency fund target ') case final r?) return 'Emergency fund target set to $r';
  return s;
}
