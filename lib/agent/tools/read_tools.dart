import '../../actions/action.dart' show In, Out;
import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../core/time/dates.dart';
import '../../features/pending/application/pending_actions.dart' show PendingResolver;
import '../../features/pending/domain/pending_payment.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../finance/finance_snapshot.dart';
import 'agent_tool.dart';
import 'json_schema.dart';

/// Read-only lookups over the signed-in user's own data. Results are
/// compact on purpose: ids, versions and the figures needed to act, never
/// the full history.

String _m(Money m) => m.toDecimalString();

/// Balances and this period's headline figures.
class FinancialOverviewTool extends ReadTool {
  const FinancialOverviewTool();

  @override
  String get name => 'get_financial_overview';

  @override
  String get progressLabel => 'Checking your balances';

  @override
  String get description =>
      'Balances (cash, earmarked, available), this budget month\'s income/expense, budgets, money to pay/collect, '
      'debt, emergency fund.';

  @override
  Map<String, Object?> get parameters => JsonSchema.object({});

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args, ToolContext context) async {
    final s = await context.loadSnapshot();
    final period = s.currentBudgetPeriod;
    final summary = s.summary(period);
    final b = s.balance;
    final budgets = s.budgetUsages;
    final upcomingSubs = s.subscriptions
        .where((x) => x.isActive && !x.nextDueDate.isBefore(s.today) && daysBetween(s.today, x.nextDueDate) <= 7)
        .toList();
    final ef = s.emergency;
    return {
      'today': Out.date(s.today),
      'balance': {'cash': _m(b.cash), 'earmarked': _m(b.earmarked), 'available': _m(b.available)},
      'budgetMonth': {
        'from': Out.date(period.start),
        'to': Out.date(period.end),
        'income': _m(summary.income),
        'expense': _m(summary.expense),
        'net': _m(summary.net),
        'transactionCount': summary.transactionCount,
      },
      'budgets': {
        'count': budgets.length,
        'overLimit': [for (final u in budgets) if (u.isOver) s.category(u.budget.categoryId)?.name ?? u.budget.categoryId],
        'nearLimit': [
          for (final u in budgets)
            if (u.health.name == 'warning') s.category(u.budget.categoryId)?.name ?? u.budget.categoryId,
        ],
      },
      'pending': {'toPay': _m(s.pendingToPay), 'toCollect': _m(s.pendingToCollect)},
      'loans': {'outstandingDebt': _m(s.totalDebt), 'overdueLoans': s.loanStates.where((l) => l.isOverdue).length},
      'subscriptions': {
        'monthlyCommitment': _m(s.monthlySubscriptionCommitment),
        'dueInNext7Days': [for (final x in upcomingSubs) {'name': x.name, 'due': Out.date(x.nextDueDate), 'amount': _m(x.amount)}],
      },
      'emergencyFund': {
        'configured': ef.plan != null,
        'saved': _m(ef.saved),
        'target': _m(ef.target),
      },
    };
  }
}

enum RecordKind { pending, goals, budgets, loans, subscriptions }

/// Finds records by name to get their exact ids before acting on them.
class FindRecordsTool extends ReadTool {
  const FindRecordsTool();

  static const maxResults = 25;

  @override
  String get name => 'find_records';

  @override
  String get progressLabel => 'Looking up your records';

  @override
  String get description =>
      'Finds records by kind and name; returns ids, versions, amounts. Use before acting on a person\'s pending '
      'payment, goal, loan, subscription or budget. Pending results include match: unique|multiple|none.';

  @override
  Map<String, Object?> get parameters => JsonSchema.object({
        'kind': {'type': 'string', 'enum': [for (final k in RecordKind.values) k.name]},
        'query': JsonSchema.string('Name or person; omit to list'),
        'direction': {'type': 'string', 'enum': ['iOwe', 'owedToMe']},
        'includeClosed': JsonSchema.boolean('Include closed/settled'),
      }, required: ['kind']);

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args, ToolContext context) async {
    final kind = In.enumeration(args, 'kind', RecordKind.values);
    final query = In.strOpt(args, 'query')?.toLowerCase();
    final includeClosed = In.boolean(args, 'includeClosed', fallback: false);
    final s = await context.loadSnapshot();
    bool matches(Iterable<String?> fields) =>
        query == null || fields.any((f) => f != null && f.toLowerCase().contains(query));

    switch (kind) {
      case RecordKind.pending:
        return _pending(s, args, query, includeClosed);
      case RecordKind.goals:
        final items = [
          for (final g in s.goalProgress)
            if ((includeClosed || g.goal.status.name == 'active') && matches([g.goal.name, g.goal.category.name]))
              {
                'id': g.goal.id,
                'version': g.goal.version,
                'name': g.goal.name,
                'status': g.goal.status.name,
                'target': _m(g.goal.target),
                'saved': _m(g.saved),
                'remaining': _m(g.remaining),
                'targetDate': Out.dateOpt(g.goal.targetDate),
              },
        ];
        return _list(items);
      case RecordKind.budgets:
        final items = [
          for (final u in s.budgetUsages)
            if (matches([s.category(u.budget.categoryId)?.name]))
              {
                'id': u.budget.id,
                'version': u.budget.version,
                'categoryId': u.budget.categoryId,
                'category': s.category(u.budget.categoryId)?.name,
                'status': u.budget.status.name,
                'limit': _m(u.budget.limit),
                'warningThresholdBps': u.budget.warningThresholdBps,
                'note': u.budget.note,
                'spentThisPeriod': _m(u.spent),
                'remaining': _m(u.remaining),
                'health': u.health.name,
              },
        ];
        return _list(items);
      case RecordKind.loans:
        final items = [
          for (final l in s.loanStates)
            if ((includeClosed || !l.isClosed) && matches([l.loan.name, l.loan.counterparty]))
              {
                'id': l.loan.id,
                'name': l.loan.name,
                'counterparty': l.loan.counterparty,
                'direction': l.loan.direction.name,
                'structure': l.loan.structure.name,
                'outstanding': _m(l.outstanding),
                'currentInstallment': _m(l.currentInstallment),
                'nextDue': l.nextDue == null
                    ? null
                    : {'date': Out.date(l.nextDue!.dueDate), 'amount': _m(l.nextDue!.payment)},
                'overdueInstallments': l.overdueCount,
                'closed': l.isClosed,
              },
        ];
        return _list(items);
      case RecordKind.subscriptions:
        final items = [
          for (final x in s.subscriptions)
            if ((includeClosed || x.status.name != 'cancelled') && matches([x.name, s.category(x.categoryId)?.name]))
              {
                'id': x.id,
                'version': x.version,
                'name': x.name,
                'status': x.status.name,
                'amount': _m(x.amount),
                'frequency': x.frequency.name,
                'nextDueDate': Out.date(x.nextDueDate),
                'categoryId': x.categoryId,
              },
        ];
        return _list(items);
    }
  }

  Map<String, Object?> _list(List<Map<String, Object?>> items) => {
        'count': items.length,
        'items': items.take(maxResults).toList(),
        if (items.length > maxResults) 'more': 'Only the first $maxResults are shown. Use a more specific query.',
      };

  Map<String, Object?> _pending(FinanceSnapshot s, Map<String, Object?> args, String? query, bool includeClosed) {
    final direction = In.enumOpt(args, 'direction', PendingDirection.values);
    Map<String, Object?> view(PendingView v) => {
          'id': v.payment.id,
          'version': v.payment.version,
          'counterparty': v.payment.counterparty,
          'direction': v.payment.direction.name,
          'purpose': v.payment.purpose,
          'original': _m(v.payment.originalAmount),
          'settled': _m(v.settled),
          'outstanding': _m(v.outstanding),
          'status': v.status.name,
          'createdDate': Out.date(v.payment.createdDate),
          'daysOpen': v.daysOpen,
          'shared': v.payment.isShared,
        };

    if (query != null && !includeClosed) {
      // Same matching rules as the app's resolver: exact name first, then
      // partial; several candidates are never narrowed down by guessing.
      final resolved = const PendingResolver().resolve(s, query, direction: direction);
      if (resolved case Ok(:final value)) {
        return {'match': 'unique', 'count': 1, 'items': [view(value)]};
      }
    }
    final candidates = [
      for (final v in s.pendingViews)
        if ((includeClosed || v.status.isActive) &&
            (direction == null || v.payment.direction == direction) &&
            (query == null ||
                v.payment.counterparty.toLowerCase().contains(query) ||
                v.payment.purpose.toLowerCase().contains(query)))
          v,
    ]..sort((a, b) => b.daysOpen.compareTo(a.daysOpen));
    return {
      'match': candidates.isEmpty ? 'none' : (candidates.length == 1 ? 'unique' : 'multiple'),
      ..._list([for (final v in candidates) view(v)]),
    };
  }
}

/// Searches transactions and totals the matches.
class SearchTransactionsTool extends ReadTool {
  const SearchTransactionsTool();

  static const defaultLimit = 10;
  static const maxLimit = 25;

  @override
  String get name => 'search_transactions';

  @override
  String get progressLabel => 'Searching transactions';

  @override
  String get description =>
      'Searches transactions (newest first) and totals all matches; returns ids and versions for edits.';

  @override
  Map<String, Object?> get parameters => JsonSchema.object({
        'query': JsonSchema.string('Text in counterparty/note/category'),
        'type': {'type': 'string', 'enum': ['income', 'expense']},
        'categoryId': {'type': 'string'},
        'from': JsonSchema.date('From date'),
        'to': JsonSchema.date('To date'),
        'minAmount': {'type': 'string'},
        'maxAmount': {'type': 'string'},
        'limit': {'type': 'integer', 'maximum': maxLimit},
      });

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args, ToolContext context) async {
    final query = In.strOpt(args, 'query')?.toLowerCase();
    final type = In.enumOpt(args, 'type', TransactionType.values);
    final categoryId = In.strOpt(args, 'categoryId');
    final from = In.dateOpt(args, 'from');
    final to = In.dateOpt(args, 'to');
    final minAmount = In.moneyOpt(args, 'minAmount');
    final maxAmount = In.moneyOpt(args, 'maxAmount');
    final limit = (In.intOpt(args, 'limit') ?? defaultLimit).clamp(1, maxLimit);
    if (from != null && to != null && to.isBefore(from)) {
      throw AppFailure.validation('"to" is before "from".', fields: {'to': 'Must be on or after from'});
    }
    final s = await context.loadSnapshot();
    final hits = s.transactions.where((t) {
      if (type != null && t.type != type) return false;
      if (categoryId != null && t.categoryId != categoryId) return false;
      if (from != null && t.date.isBefore(from)) return false;
      if (to != null && t.date.isAfter(to)) return false;
      if (minAmount != null && t.amount < minAmount) return false;
      if (maxAmount != null && t.amount > maxAmount) return false;
      if (query != null) {
        final hay = '${t.counterparty ?? ''} ${t.note ?? ''} ${s.category(t.categoryId)?.name ?? ''}'.toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList();
    final income = Money.sum(hits.where((t) => t.type == TransactionType.income).map((t) => t.amount));
    final expense = Money.sum(hits.where((t) => t.type == TransactionType.expense).map((t) => t.amount));
    return {
      'matchCount': hits.length,
      'totalIncome': _m(income),
      'totalExpense': _m(expense),
      'transactions': [
        for (final t in hits.take(limit))
          {
            'id': t.id,
            'version': t.version,
            'type': t.type.name,
            'amount': _m(t.amount),
            'categoryId': t.categoryId,
            'category': s.category(t.categoryId)?.name,
            'date': Out.date(t.date),
            'paymentMethod': t.paymentMethod?.name,
            'counterparty': t.counterparty,
            'note': t.note,
            // Linked transactions belong to a loan, settlement or
            // subscription and cannot be edited directly.
            if (t.isLinked) 'linkedTo': t.origin.name,
          },
      ],
    };
  }
}
