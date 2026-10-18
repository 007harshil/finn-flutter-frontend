import '../../actions/action.dart' show Out;
import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../core/time/frequency.dart';
import '../../features/accounts/domain/money_account.dart';
import '../../features/categories/domain/category.dart';
import '../../features/goals/domain/goal.dart';
import '../../features/loans/domain/loan_calculator.dart';
import '../../features/pending/domain/pending_payment.dart';
import '../../features/subscriptions/domain/subscription.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../finance/finance_snapshot.dart';
import '../orchestration/agent_memory.dart';
import 'agent_plan.dart';
import 'resolvers.dart';

/// What one plan op becomes after deterministic resolution.
sealed class OpOutcome {
  const OpOutcome();
}

/// A registered action with exact input, ready to preview. Fields listed
/// in [refs] get the id of the record another op of this plan creates
/// (`input[field]` holds a placeholder until then).
final class OpAction extends OpOutcome {
  const OpAction(this.actionId, this.input, {this.refs = const {}, this.notes = const []});
  final String actionId;
  final Map<String, Object?> input;

  /// Input field → ref of the op whose new record id fills it.
  final Map<String, String> refs;

  /// Shown on the review card, e.g. "No Pets category, so it goes under
  /// Other Expense."
  final List<String> notes;
}

/// The op names a record that already exists (e.g. a category the user
/// asked to create but already has). Later ops referring to it use [recordId].
final class OpExisting extends OpOutcome {
  const OpExisting(this.recordId, this.note);
  final String recordId;
  final String note;
}

/// An essential detail is missing or ambiguous: ask instead of guessing.
final class OpQuestion extends OpOutcome {
  const OpQuestion(this.question, {this.field, this.options = const []});
  final String question;

  /// The op field the answer fills (`amount`, or `_id` for a chosen record).
  final String? field;
  final List<ClarifyOption> options;
}

/// The op cannot be carried out; [reason] is safe to show.
final class OpRejected extends OpOutcome {
  const OpRejected(this.reason);
  final String reason;
}

/// A read-only answer computed from the user's data.
final class OpAnswer extends OpOutcome {
  const OpAnswer(this.text);
  final String text;
}

/// The user asked about earlier agent activity: answered from history.
final class OpHistory extends OpOutcome {
  const OpHistory({this.period});
  final String? period;
}

/// Everything an op needs to resolve against the user's own data.
class OpContext {
  OpContext({
    required this.snapshot,
    required this.today,
    required this.userText,
    required this.memory,
    this.groundingText = '',
    this.answer,
  });

  final FinanceSnapshot snapshot;

  /// Today in the user's configured time zone.
  final DateTime today;

  /// The user's message, to check that optional details were really said.
  final String userText;
  final AgentMemory memory;

  /// More text the user said earlier in this request (an open question).
  final String groundingText;

  /// Answers `q` ops (see `data_answers.dart`).
  final String Function(Map<String, Object?> args, FinanceSnapshot s, DateTime today)? answer;
}

typedef OpCompiler = OpOutcome Function(PlanOp op, OpContext ctx);

/// One op type of the plan format and the action(s) it maps to.
class OpSpec {
  const OpSpec(this.type, this.actionIds, this.compile);
  final String type;

  /// Registered actions this op may produce (empty for read-only ops). The
  /// runner checks they exist and are allowed for the agent.
  final Set<String> actionIds;
  final OpCompiler compile;
}

/// Every op type the model may use. Adding an operation = one entry here, a
/// line in `agentInstructions`, and the action it maps to.
final Map<String, OpSpec> opCatalog = {
  for (final s in <OpSpec>[
    OpSpec('expense', {'transactions.create'}, (op, c) => _transaction(op, c, TransactionType.expense)),
    OpSpec('income', {'transactions.create'}, (op, c) => _transaction(op, c, TransactionType.income)),
    const OpSpec('pending', {'pending.create'}, _pending),
    const OpSpec('settle', {'pending.settle'}, _settle),
    const OpSpec('write_off', {'pending.cancel'}, _writeOff),
    const OpSpec('split', {'pending.split'}, _split),
    const OpSpec('edit', {'transactions.update'}, _edit),
    const OpSpec('undo', {}, _undo),
    const OpSpec('category', {'categories.create'}, _category),
    const OpSpec('budget', {'budgets.create', 'budgets.update'}, _budget),
    const OpSpec('budget_pause', {'budgets.setPaused'}, _budgetPause),
    const OpSpec('loan_pay', {'loans.recordPayment'}, _loanPay),
    const OpSpec('loan', {'loans.create'}, _loan),
    const OpSpec('sub_paid', {'subscriptions.markPaid'}, _subPaid),
    const OpSpec('sub_status', {'subscriptions.setStatus'}, _subStatus),
    const OpSpec('sub_skip', {'subscriptions.skipCycle'}, _subSkip),
    const OpSpec('subscription', {'subscriptions.create'}, _subscription),
    const OpSpec('goal', {'goals.create'}, _goal),
    OpSpec('goal_add', {'goals.contribute'}, (op, c) => _goalMove(op, c, 'goals.contribute')),
    OpSpec('goal_take', {'goals.withdraw'}, (op, c) => _goalMove(op, c, 'goals.withdraw')),
    OpSpec('fund_add', {'emergencyFund.contribute'}, (op, c) => _fund(op, c, 'emergencyFund.contribute')),
    OpSpec('fund_take', {'emergencyFund.withdraw'}, (op, c) => _fund(op, c, 'emergencyFund.withdraw')),
    const OpSpec('account', {'accounts.create'}, _account),
    const OpSpec('transfer', {'transfers.create'}, _transfer),
    const OpSpec('q', {}, _question),
    const OpSpec('history', {}, _history),
  ])
    s.type: s,
};

/// Compiles [op], turning field problems into a question about the field.
OpOutcome compileOp(PlanOp op, OpContext ctx) {
  final spec = opCatalog[op.type];
  if (spec == null) return OpRejected('I can\'t do "${op.type}" yet.');
  try {
    return spec.compile(op, ctx);
  } on FieldProblem catch (p) {
    return OpQuestion('${p.message} ${_askFor(p.field, op)}', field: p.field);
  }
}

// ---------------------------------------------------------------------------
// Field helpers
// ---------------------------------------------------------------------------

String? _str(Object? v, {int max = 120}) {
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty) return null;
  return t.length <= max ? t : t.substring(0, max);
}

/// `"@o1"` → `o1`.
String? _ref(Object? v) => v is String && RegExp(r'^@o\d{1,2}$').hasMatch(v.trim()) ? v.trim().substring(1) : null;

String _askFor(String field, PlanOp op) => switch (field) {
  'amount' || 'total' || 'limit' || 'target' || 'principal' => 'How much was it?',
  'date' || 'next' || 'first_due' || 'start' => 'Which date was it?',
  _ => 'Could you say that again?',
};

Money? _money(PlanOp op, String field) => AgentAmount.parse(op.args[field], field: field);

DateTime _date(PlanOp op, OpContext c, [String field = 'date']) =>
    AgentDate.resolve(op.args[field], c.today, field: field) ?? c.today;

String _what(PlanOp op, String fallback) => _str(op.args['note'], max: 40) ?? _str(op.args['category'], max: 40) ?? fallback;

const _genericPeople = {
  'friend', 'a friend', 'my friend', 'someone', 'somebody', 'him', 'her', 'them', 'colleague', 'a colleague',
  'bhai', 'brother', 'sister', 'cousin', 'neighbour', 'neighbor', 'person', 'guy',
};

/// The person an op names, or a question when it is missing, generic
/// ("a friend") or not something the user said.
Object _person(PlanOp op, OpContext c, String question) {
  final p = _str(op.args['person'], max: 60);
  if (p == null || _genericPeople.contains(p.toLowerCase())) return OpQuestion(question, field: 'person');
  if (!grounded(p, c.userText, extra: c.groundingText)) return OpQuestion(question, field: 'person');
  return p;
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _fmtDate(DateTime d) => '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

/// Category id for a transaction-like op: an exact match, a reference to a
/// category created in this plan, or the "other" category with a note.
({String id, String? ref, String? note})? _categoryFor(Object? raw, FinanceSnapshot s, TransactionType type) {
  final ref = _ref(raw);
  if (ref != null) return (id: '@$ref', ref: ref, note: null);
  final name = _str(raw, max: 60);
  final found = name == null ? null : findCategory(s, name, type);
  if (found != null) return (id: found.id, ref: null, note: null);
  final other = otherCategory(s, type);
  if (other == null) return null;
  return (id: other.id, ref: null, note: name == null ? null : 'No "$name" category, so it goes under ${other.name}.');
}

// ---------------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------------

OpOutcome _transaction(PlanOp op, OpContext c, TransactionType type) {
  final what = _what(op, type == TransactionType.income ? 'income' : 'expense');
  final amount = _money(op, 'amount');
  if (amount == null) {
    return OpQuestion(
      type == TransactionType.income ? 'How much was the $what?' : 'How much did you spend on $what?',
      field: 'amount',
    );
  }
  final category = _categoryFor(op.args['category'], c.snapshot, type);
  if (category == null) return const OpRejected('There is no category to file this under.');
  final party = _str(op.args['party'], max: 60);
  return OpAction(
    'transactions.create',
    {
      'type': type.name,
      'amount': Out.money(amount),
      'categoryId': category.id,
      'date': Out.date(_date(op, c)),
      'accountId': AgentAccount.resolve(c.snapshot, op.args['account'], c.userText),
      'channel': AgentChannel.resolve(op.args['channel'], c.userText),
      'counterparty': party != null && grounded(party, c.userText, extra: c.groundingText) ? party : null,
      'note': _str(op.args['note']),
    },
    refs: {if (category.ref != null) 'categoryId': category.ref!},
    notes: [?category.note],
  );
}

/// The transaction an edit targets: a recent change (`#1`), a search, or
/// the record chosen in a clarification.
Object _editTarget(PlanOp op, OpContext c) {
  final s = c.snapshot;
  final chosen = _str(op.args['_id']);
  if (chosen != null) return s.transactionById[chosen] ?? const OpRejected('That transaction no longer exists.');
  final target = op.args['target'];
  if (target is String && !target.trim().startsWith('{')) {
    final recent = c.memory.resolve(target);
    if (recent == null) return const OpRejected('I don\'t know which change you mean. Say what it was for.');
    if (recent.actionId != 'transactions.create' && recent.actionId != 'transactions.update') {
      return const OpRejected('I can only change income and expenses this way. Open the record to edit it.');
    }
    return s.transactionById[recent.recordId] ?? const OpRejected('That transaction no longer exists.');
  }
  final find = target is Map ? target : const {};
  final text = _str(find['text'], max: 60);
  final date = AgentDate.resolve(find['date'], c.today);
  final amount = AgentAmount.parse(find['amount']);
  if (text == null && date == null && amount == null) return const OpRejected('I don\'t know which transaction you mean.');
  final hits = [
    for (final t in s.transactions)
      if ((date == null || t.date == date) &&
          (amount == null || t.amount == amount) &&
          (text == null ||
              matchByName(text, [t], (x) => [x.note ?? '', x.counterparty ?? '', s.category(x.categoryId)?.name ?? '']) is! NoMatch))
        t,
  ];
  if (hits.isEmpty) return const OpRejected('I couldn\'t find that transaction.');
  if (hits.length == 1) return hits.single;
  String label(Transaction t) =>
      '${t.amount.format()} ${s.category(t.categoryId)?.name ?? ''} on ${_fmtDate(t.date)}${t.note == null ? '' : ' (${t.note})'}';
  final options = [for (final t in hits.take(4)) ClarifyOption(label: label(t), value: t.id, amount: t.amount)];
  return OpQuestion('Which one: ${options.map((o) => o.label).join(', ')}?', field: '_id', options: options);
}

OpOutcome _edit(PlanOp op, OpContext c) {
  final found = _editTarget(op, c);
  if (found is OpOutcome) return found;
  final tx = found as Transaction;
  if (tx.isLinked) {
    return const OpRejected('That entry belongs to a loan, settlement or subscription. Change it there.');
  }
  // Changed fields may sit in "set" or, loosely, at the top level.
  final set = <String, Object?>{
    for (final k in ['amount', 'category', 'date', 'note', 'party', 'account', 'channel', 'type']) k: ?op.args[k],
    if (op.args['set'] is Map) ...Map<String, Object?>.from(op.args['set'] as Map),
  };
  if (set.isEmpty) return const OpQuestion('What should I change?');
  final type = switch (set['type']) {
    'income' => TransactionType.income,
    'expense' => TransactionType.expense,
    _ => tx.type,
  };
  final notes = <String>[];
  var categoryId = tx.categoryId;
  if (set['category'] != null || type != tx.type) {
    final category = _categoryFor(set['category'], c.snapshot, type);
    if (category == null || category.ref != null) return const OpRejected('I couldn\'t find that category.');
    categoryId = category.id;
    if (category.note != null) notes.add(category.note!);
  }
  final amount = AgentAmount.parse(set['amount']) ?? tx.amount;
  final date = AgentDate.resolve(set['date'], c.today) ?? tx.date;
  final accountId = set.containsKey('account')
      ? AgentAccount.resolve(c.snapshot, set['account'], c.userText) ?? tx.accountId
      : tx.accountId;
  final channel = set.containsKey('channel') ? AgentChannel.resolve(set['channel'], c.userText) : tx.channel;
  return OpAction(
    'transactions.update',
    {
      'id': tx.id,
      'expectedVersion': tx.version,
      'type': type.name,
      'amount': Out.money(amount),
      'categoryId': categoryId,
      'date': Out.date(date),
      'accountId': accountId,
      'channel': channel,
      'counterparty': set.containsKey('party') ? _str(set['party'], max: 60) : tx.counterparty,
      'note': set.containsKey('note') ? _str(set['note']) : tx.note,
    },
    notes: notes,
  );
}

/// The account an op names for [field], or a question listing the user's
/// accounts when it is missing or ambiguous.
Object _accountFor(PlanOp op, OpContext c, String field, String question) {
  final raw = op.args[field];
  final m = AgentAccount.match(c.snapshot, raw, '${c.userText} ${c.groundingText}');
  if (m is Matched<MoneyAccount>) return m.value;
  final pool = m is Ambiguous<MoneyAccount> ? m.candidates : c.snapshot.activeAccounts;
  return OpQuestion(
    question,
    field: field,
    options: [for (final a in pool.take(6)) ClarifyOption(label: a.name, value: a.id)],
  );
}

OpOutcome _transfer(PlanOp op, OpContext c) {
  final amount = _money(op, 'amount');
  if (amount == null) return const OpQuestion('How much was moved?', field: 'amount');
  final from = _accountFor(op, c, 'from', 'Which account did the money leave?');
  if (from is OpOutcome) return from;
  final to = _accountFor(op, c, 'to', 'Which account did the money go to?');
  if (to is OpOutcome) return to;
  if ((from as MoneyAccount).id == (to as MoneyAccount).id) {
    return const OpRejected('A transfer needs two different accounts.');
  }
  return OpAction('transfers.create', {
    'fromAccountId': from.id,
    'toAccountId': to.id,
    'amount': Out.money(amount),
    'date': Out.date(_date(op, c)),
    'channel': AgentChannel.resolve(op.args['channel'], c.userText),
    'note': _str(op.args['note']),
  });
}

MoneyAccountKind? _accountKind(Object? v) => switch (v is String ? v.trim().toLowerCase() : null) {
  'cash' => MoneyAccountKind.cash,
  'bank' || 'savings' || 'current' || 'account' => MoneyAccountKind.bank,
  'debit' || 'debitcard' || 'debit card' => MoneyAccountKind.debitCard,
  'credit' || 'creditcard' || 'credit card' => MoneyAccountKind.creditCard,
  'promo' || 'gift' || 'promocard' || 'gift card' => MoneyAccountKind.promoCard,
  'card' || 'othercard' || 'other card' => MoneyAccountKind.otherCard,
  _ => null,
};

OpOutcome _account(PlanOp op, OpContext c) {
  final name = _str(op.args['name'], max: 40);
  if (name == null) return const OpQuestion('What should the account be called?', field: 'name');
  final kind = _accountKind(op.args['kind']);
  if (kind == null) return const OpQuestion('Is it cash, a bank account, a debit card or a credit card?', field: 'kind');
  final last4 = _str(op.args['last4'], max: 4);
  final limit = _money(op, 'limit');
  return OpAction('accounts.create', {
    'name': name,
    'kind': kind.name,
    'openingBalance': Out.money(_money(op, 'balance') ?? Money.zero),
    if (last4 != null && kind.isCard && RegExp(r'^\d{4}$').hasMatch(last4)) 'last4': last4,
    if (limit != null && kind == MoneyAccountKind.creditCard) 'creditLimit': Out.money(limit),
  });
}

OpOutcome _undo(PlanOp op, OpContext c) {
  final recent = c.memory.resolve(op.args['target']);
  return OpAnswer(
    recent == null
        ? 'I can\'t delete records. Open the record in the app to delete it.'
        : 'I can\'t delete records. To remove "${recent.summary}", open it from Activity and delete it there.',
  );
}

OpOutcome _category(PlanOp op, OpContext c) {
  final name = _str(op.args['name'], max: 30);
  if (name == null || name.length < 2) return const OpQuestion('What should the new category be called?', field: 'name');
  final type = op.args['type'] == 'income' ? TransactionType.income : TransactionType.expense;
  final existing = c.snapshot.categories
      .where((x) => !x.isArchived && x.type == type && x.name.toLowerCase() == name.toLowerCase())
      .firstOrNull;
  if (existing != null) return OpExisting(existing.id, 'You already have a "${existing.name}" category, so I used it.');
  return OpAction('categories.create', {
    'name': _cap(name),
    'type': type.name,
    'iconKey': 'tag',
    'colorIndex': name.codeUnits.fold<int>(0, (a, b) => a + b) % 14,
    'description': '',
  });
}

// ---------------------------------------------------------------------------
// Pending payments
// ---------------------------------------------------------------------------

PendingDirection? _dir(Object? v) => switch (v) {
  'collect' || 'owedToMe' => PendingDirection.owedToMe,
  'owe' || 'iOwe' => PendingDirection.iOwe,
  _ => null,
};

OpOutcome _pending(PlanOp op, OpContext c) {
  final dir = _dir(op.args['dir']);
  final person = _person(op, c, 'Who is this with?');
  if (person is OpQuestion) return person;
  final name = person as String;
  if (dir == null) return OpQuestion('Does $name owe you, or do you owe $name?', field: 'dir');
  final amount = _money(op, 'amount');
  if (amount == null) {
    return OpQuestion(dir == PendingDirection.owedToMe ? 'How much does $name owe you?' : 'How much do you owe $name?',
        field: 'amount');
  }
  final kind = switch (op.args['kind']) {
    'lent' => PendingKind.lent,
    'borrowed' => PendingKind.borrowed,
    'shared' || 'sharedExpense' => PendingKind.sharedExpense,
    'reimbursement' => PendingKind.reimbursement,
    _ => PendingKind.other,
  };
  return OpAction('pending.create', {
    'counterparty': _cap(name),
    'direction': dir.name,
    'kind': kind.name,
    'amount': Out.money(amount),
    'purpose': _str(op.args['note'], max: 80) ?? (kind == PendingKind.other ? 'Money owed' : kind.label),
    'createdDate': Out.date(_date(op, c)),
  });
}

/// The open pending item an op refers to: by person, then narrowed by
/// direction, amount and what it was for. Several left → a question.
Object _openPending(PlanOp op, OpContext c, {required String verb}) {
  final s = c.snapshot;
  final chosen = _str(op.args['_id']);
  final open = s.pendingViews.where((v) => v.status.isActive).toList();
  if (chosen != null) {
    return open.where((v) => v.payment.id == chosen).firstOrNull ?? const OpRejected('That item is no longer open.');
  }
  final person = _str(op.args['person'], max: 60);
  if (person == null) return OpQuestion('Who $verb?', field: 'person');
  final dir = _dir(op.args['dir']);
  final scoped = [for (final v in open) if (dir == null || v.payment.direction == dir) v];
  final match = matchByName(person, scoped, (v) => [v.payment.counterparty]);
  var list = switch (match) {
    Matched(:final value) => [value],
    Ambiguous(:final candidates) => candidates,
    NoMatch() => <PendingView>[],
  };
  if (list.isEmpty) return OpRejected('There is no open pending payment with $person.');
  final amount = AgentAmount.parse(op.args['amount']);
  if (list.length > 1 && amount != null) {
    final exact = [for (final v in list) if (v.outstanding == amount || v.payment.originalAmount == amount) v];
    if (exact.isNotEmpty) list = exact;
  }
  final note = _str(op.args['note'], max: 60);
  if (list.length > 1 && note != null) {
    final byPurpose = matchByName(note, list, (v) => [v.payment.purpose]);
    if (byPurpose is Matched<PendingView>) list = [byPurpose.value];
  }
  if (list.length == 1) return list.single;
  String label(PendingView v) =>
      '${v.payment.purpose} (${v.outstanding.format()} ${v.payment.direction == PendingDirection.iOwe ? 'you owe' : 'to collect'})';
  final options = [
    for (final v in list.take(5)) ClarifyOption(label: label(v), value: v.payment.id, amount: v.outstanding),
  ];
  return OpQuestion(
    'Which one with ${list.first.payment.counterparty}: ${options.map((o) => o.label).join(' or ')}?',
    field: '_id',
    options: options,
  );
}

OpOutcome _settle(PlanOp op, OpContext c) {
  final found = _openPending(op, c, verb: 'paid back');
  if (found is OpOutcome) return found;
  final v = found as PendingView;
  final amount = _money(op, 'amount') ?? v.outstanding;
  if (amount > v.outstanding) {
    return OpRejected('Only ${v.outstanding.format()} is still open with ${v.payment.counterparty} for ${v.payment.purpose}.');
  }
  return OpAction('pending.settle', {
    'pendingId': v.payment.id,
    'amount': Out.money(amount),
    'date': Out.date(_date(op, c)),
    'accountId': AgentAccount.resolve(c.snapshot, op.args['account'], c.userText),
    'channel': AgentChannel.resolve(op.args['channel'], c.userText),
    'recordCashMovement': true,
  });
}

OpOutcome _writeOff(PlanOp op, OpContext c) {
  final found = _openPending(op, c, verb: 'will not pay');
  if (found is OpOutcome) return found;
  return OpAction('pending.cancel', {'id': (found as PendingView).payment.id});
}

OpOutcome _split(PlanOp op, OpContext c) {
  final total = _money(op, 'total');
  if (total == null) return const OpQuestion('How much was the whole bill?', field: 'total');
  final raw = op.args['people'];
  final names = [
    for (final n in (raw is List ? raw : (raw is String ? raw.split(RegExp(r',|\band\b')) : const [])))
      if (n is String && n.trim().isNotEmpty && !{'me', 'myself', 'i', 'you'}.contains(n.trim().toLowerCase())) _cap(n.trim()),
  ];
  if (names.isEmpty) return const OpQuestion('Who shared the bill with you?', field: 'people');
  for (final n in names) {
    if (!grounded(n, c.userText, extra: c.groundingText)) return const OpQuestion('Who shared the bill with you?', field: 'people');
  }
  return OpAction('pending.split', {
    'direction': PendingDirection.owedToMe.name,
    'kind': PendingKind.sharedExpense.name,
    'total': Out.money(total),
    'purpose': _str(op.args['note'], max: 80) ?? 'Shared bill',
    'createdDate': Out.date(_date(op, c)),
    'method': 'equally',
    'includeMe': op.args['me'] != false,
    'people': [for (final n in names) {'counterparty': n}],
  });
}

// ---------------------------------------------------------------------------
// Budgets, loans, subscriptions, goals, emergency fund
// ---------------------------------------------------------------------------

Object _expenseCategory(PlanOp op, OpContext c) {
  final raw = op.args['category'];
  final name = _str(raw, max: 60);
  if (name == null) return const OpQuestion('Which spending category?', field: 'category');
  return findCategory(c.snapshot, name, TransactionType.expense) ?? OpRejected('There is no "$name" spending category.');
}

OpOutcome _budget(PlanOp op, OpContext c) {
  final ref = _ref(op.args['category']);
  final limit = _money(op, 'limit');
  if (limit == null) return const OpQuestion('What monthly limit should it have?', field: 'limit');
  if (ref != null) {
    return OpAction('budgets.create', {'categoryId': '@$ref', 'limit': Out.money(limit)}, refs: {'categoryId': ref});
  }
  final found = _expenseCategory(op, c);
  if (found is OpOutcome) return found;
  final category = found as TransactionCategory;
  final existing = c.snapshot.budgets.where((b) => b.categoryId == category.id).firstOrNull;
  if (existing == null) return OpAction('budgets.create', {'categoryId': category.id, 'limit': Out.money(limit)});
  return OpAction('budgets.update', {
    'id': existing.id,
    'expectedVersion': existing.version,
    'categoryId': category.id,
    'limit': Out.money(limit),
    'warningThresholdBps': existing.warningThresholdBps,
    'note': existing.note,
  });
}

OpOutcome _budgetPause(PlanOp op, OpContext c) {
  final found = _expenseCategory(op, c);
  if (found is OpOutcome) return found;
  final category = found as TransactionCategory;
  final budget = c.snapshot.budgets.where((b) => b.categoryId == category.id).firstOrNull;
  if (budget == null) return OpRejected('There is no budget for ${category.name}.');
  return OpAction('budgets.setPaused', {'id': budget.id, 'paused': op.args['paused'] != false});
}

/// A named record among [items], or a question / rejection.
Object _named<T extends Object>(PlanOp op, String field, Iterable<T> items, Iterable<String> Function(T) labels, String Function(T) id,
    {required String what}) {
  final list = items.toList();
  final chosen = _str(op.args['_id']);
  if (chosen != null) return list.where((x) => id(x) == chosen).firstOrNull ?? OpRejected('That $what no longer exists.');
  final query = _str(op.args[field], max: 60);
  if (query == null) {
    if (list.length == 1) return list.single;
    final options = [for (final x in list.take(5)) ClarifyOption(label: labels(x).first, value: id(x))];
    if (options.isEmpty) return OpRejected('You don\'t have any ${what}s yet.');
    return OpQuestion('Which $what: ${options.map((o) => o.label).join(', ')}?', field: '_id', options: options);
  }
  return switch (matchByName(query, list, labels)) {
    Matched(:final value) => value,
    Ambiguous(:final candidates) => OpQuestion(
      'Which $what: ${candidates.take(5).map((x) => labels(x).first).join(', ')}?',
      field: '_id',
      options: [for (final x in candidates.take(5)) ClarifyOption(label: labels(x).first, value: id(x))],
    ),
    NoMatch() => OpRejected('You don\'t have a $what called "$query".'),
  };
}

OpOutcome _loanPay(PlanOp op, OpContext c) {
  final found = _named<LoanState>(
    op,
    'loan',
    c.snapshot.loanStates.where((l) => !l.isClosed),
    (l) => [l.loan.name, l.loan.counterparty],
    (l) => l.loan.id,
    what: 'loan',
  );
  if (found is OpOutcome) return found;
  final l = found as LoanState;
  final amount = _money(op, 'amount') ?? l.nextDue?.payment ?? l.currentInstallment;
  final kind = switch (op.args['kind']) {
    'interest' => 'interest',
    'principal' || 'prepay' || 'prepayment' => 'principal',
    _ => 'installment',
  };
  return OpAction('loans.recordPayment', {
    'loanId': l.loan.id,
    'kind': kind,
    'amount': Out.money(amount),
    'date': Out.date(_date(op, c)),
    'accountId': AgentAccount.resolve(c.snapshot, op.args['account'], c.userText),
    'channel': AgentChannel.resolve(op.args['channel'], c.userText),
    'recordCashMovement': true,
  });
}

Frequency? _every(Object? v) => switch (v) {
  null || 'monthly' || 'month' => Frequency.monthly,
  'weekly' || 'week' => Frequency.weekly,
  'quarterly' || 'quarter' => Frequency.quarterly,
  'half-yearly' || 'halfYearly' || 'half_yearly' => Frequency.halfYearly,
  'yearly' || 'annual' || 'annually' || 'year' => Frequency.yearly,
  _ => null,
};

OpOutcome _loan(PlanOp op, OpContext c) {
  final name = _str(op.args['name'], max: 40);
  final lender = _str(op.args['lender'], max: 60);
  final principal = _money(op, 'principal');
  final rate = op.args['rate'] is num ? (op.args['rate'] as num).toDouble() : double.tryParse('${op.args['rate'] ?? ''}'.replaceAll('%', ''));
  final emis = op.args['emis'] is num ? (op.args['emis'] as num).toInt() : int.tryParse('${op.args['emis'] ?? ''}');
  final firstDue = AgentDate.resolve(op.args['first_due'], c.today, field: 'first_due');
  final missing = [
    if (principal == null) 'the loan amount',
    if (rate == null) 'the yearly interest rate',
    if (emis == null) 'the number of EMIs',
    if (firstDue == null) 'the first EMI date',
    if (lender == null) 'the lender',
  ];
  if (missing.isNotEmpty) return OpQuestion('To add this loan I need ${missing.join(', ')}.');
  return OpAction('loans.create', {
    'name': name ?? 'Loan from $lender',
    'counterparty': lender,
    'direction': op.args['dir'] == 'lent' ? 'lent' : 'borrowed',
    'structure': 'amortizing',
    'principal': Out.money(principal!),
    'rateBps': (rate! * 100).round(),
    'startDate': Out.date(_date(op, c, 'start')),
    'firstDueDate': Out.date(firstDue!),
    'frequency': (_every(op.args['every']) ?? Frequency.monthly).name,
    'tenureInstallments': emis,
    'recordDisbursement': false,
  });
}

Object _subscriptionNamed(PlanOp op, OpContext c, {bool includeCancelled = false}) => _named<Subscription>(
  op,
  'name',
  c.snapshot.subscriptions.where((x) => includeCancelled || x.status != SubscriptionStatus.cancelled),
  (x) => [x.name],
  (x) => x.id,
  what: 'subscription',
);

OpOutcome _subPaid(PlanOp op, OpContext c) {
  final found = _subscriptionNamed(op, c);
  if (found is OpOutcome) return found;
  final sub = found as Subscription;
  return OpAction('subscriptions.markPaid', {
    'subscriptionId': sub.id,
    'date': Out.date(_date(op, c)),
    'amount': ?Out.moneyOpt(_money(op, 'amount')),
    'accountId': AgentAccount.resolve(c.snapshot, op.args['account'], c.userText),
    'channel': AgentChannel.resolve(op.args['channel'], c.userText),
  });
}

OpOutcome _subStatus(PlanOp op, OpContext c) {
  final status = SubscriptionStatus.values.where((s) => s.name == op.args['status']).firstOrNull;
  if (status == null) return const OpQuestion('Should it be active, paused or cancelled?', field: 'status');
  final found = _subscriptionNamed(op, c, includeCancelled: true);
  if (found is OpOutcome) return found;
  return OpAction('subscriptions.setStatus', {'id': (found as Subscription).id, 'status': status.name});
}

OpOutcome _subSkip(PlanOp op, OpContext c) {
  final found = _subscriptionNamed(op, c);
  if (found is OpOutcome) return found;
  return OpAction('subscriptions.skipCycle', {'subscriptionId': (found as Subscription).id});
}

OpOutcome _subscription(PlanOp op, OpContext c) {
  final name = _str(op.args['name'], max: 40);
  if (name == null) return const OpQuestion('What is the subscription called?', field: 'name');
  final amount = _money(op, 'amount');
  if (amount == null) return OpQuestion('How much is $name each time?', field: 'amount');
  final every = _every(op.args['every']);
  if (every == null) return OpQuestion('How often does $name renew?', field: 'every');
  final next = AgentDate.resolve(op.args['next'], c.today, field: 'next');
  if (next == null) return OpQuestion('When does $name renew next?', field: 'next');
  final category = _categoryFor(op.args['category'] ?? 'Subscriptions', c.snapshot, TransactionType.expense);
  if (category == null) return const OpRejected('There is no category to file this under.');
  return OpAction(
    'subscriptions.create',
    {
      'name': name,
      'amount': Out.money(amount),
      'categoryId': category.id,
      'frequency': every.name,
      'nextDueDate': Out.date(next),
      'autoRenews': true,
    },
    refs: {if (category.ref != null) 'categoryId': category.ref!},
    notes: [?category.note],
  );
}

OpOutcome _goal(PlanOp op, OpContext c) {
  final name = _str(op.args['name'], max: 40);
  if (name == null) return const OpQuestion('What is the goal called?', field: 'name');
  final target = _money(op, 'target');
  if (target == null) return OpQuestion('How much do you want to save for $name?', field: 'target');
  return OpAction('goals.create', {
    'name': _cap(name),
    'category': GoalCategory.other.name,
    'target': Out.money(target),
    'targetDate': Out.dateOpt(AgentDate.resolve(op.args['by'], c.today, field: 'by')),
    'plannedMonthlyContribution': Out.moneyOpt(_money(op, 'monthly')),
  });
}

OpOutcome _goalMove(PlanOp op, OpContext c, String actionId) {
  final amount = _money(op, 'amount');
  final ref = _ref(op.args['goal']);
  if (ref != null) {
    if (amount == null) return const OpQuestion('How much?', field: 'amount');
    return OpAction(actionId, {'goalId': '@$ref', 'amount': Out.money(amount), ..._onAccount(op, c), 'date': Out.date(_date(op, c))},
        refs: {'goalId': ref});
  }
  final found = _named<SavingsGoal>(
    op,
    'goal',
    c.snapshot.goals.where((g) => g.status == GoalStatus.active),
    (g) => [g.name],
    (g) => g.id,
    what: 'goal',
  );
  if (found is OpOutcome) return found;
  final goal = found as SavingsGoal;
  if (amount == null) {
    return OpQuestion(
      actionId == 'goals.contribute' ? 'How much should I add to ${goal.name}?' : 'How much should I take from ${goal.name}?',
      field: 'amount',
    );
  }
  return OpAction(actionId, {'goalId': goal.id, 'amount': Out.money(amount), ..._onAccount(op, c), 'date': Out.date(_date(op, c))});
}

/// `accountId` when the user named an account for a set-aside or release;
/// otherwise nothing (default account / the accounts holding the most).
Map<String, Object?> _onAccount(PlanOp op, OpContext c) {
  final id = AgentAccount.resolve(c.snapshot, op.args['account'], c.userText);
  return id == null ? const {} : {'accountId': id};
}

OpOutcome _fund(PlanOp op, OpContext c, String actionId) {
  final amount = _money(op, 'amount');
  if (amount == null) return const OpQuestion('How much?', field: 'amount');
  return OpAction(actionId, {'amount': Out.money(amount), ..._onAccount(op, c), 'date': Out.date(_date(op, c))});
}

// ---------------------------------------------------------------------------
// Read-only
// ---------------------------------------------------------------------------

OpOutcome _question(PlanOp op, OpContext c) {
  final answer = c.answer;
  if (answer == null) return const OpRejected('I can\'t look that up right now.');
  return OpAnswer(answer(op.args, c.snapshot, c.today));
}

OpOutcome _history(PlanOp op, OpContext c) => OpHistory(period: _str(op.args['period'], max: 20));
