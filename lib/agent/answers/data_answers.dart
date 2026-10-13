import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../core/time/dates.dart';
import '../../features/pending/domain/pending_payment.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../finance/finance_snapshot.dart';
import '../plan/resolvers.dart';

/// Answers questions about the user's own records (`q` ops) from the synced
/// snapshot, with ordinary code: no second model call, exact figures.
abstract final class DataAnswers {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _d(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static String _range(DateRange r) =>
      r.start == r.end ? _d(r.start) : '${_d(r.start)}–${_d(r.end)}${r.end.year != r.start.year ? ' ${r.end.year}' : ''}';

  /// The date range a `q` op asks about, with a label such as "this month".
  static (DateRange, String) period(Map<String, Object?> args, FinanceSnapshot s, DateTime today) {
    DateTime? date(Object? v) {
      try {
        return AgentDate.resolve(v, today);
      } on FieldProblem {
        return null;
      }
    }

    final from = date(args['from']);
    final to = date(args['to']);
    if (from != null || to != null) {
      final start = from ?? DateTime(2000);
      final end = to ?? today;
      final r = DateRange(start.isAfter(end) ? end : start, end);
      return (r, _range(r));
    }
    final month = FinanceSnapshot.budgetCalc.monthlyPeriod(today, s.monthStartDay);
    return switch (args['period']) {
      'today' => (DateRange(today, today), 'today'),
      'yesterday' => (DateRange(today.subtract(const Duration(days: 1)), today.subtract(const Duration(days: 1))), 'yesterday'),
      'week' => (DateRange(today.subtract(Duration(days: today.weekday - 1)), today), 'this week'),
      'last_month' => () {
        final r = FinanceSnapshot.budgetCalc.monthlyPeriod(month.start.subtract(const Duration(days: 1)), s.monthStartDay);
        return (r, 'last month (${_range(r)})');
      }(),
      'year' => (DateRange(DateTime(today.year), today), 'this year'),
      'all' => (DateRange(DateTime(2000), today), 'in total'),
      _ => (DateRange(month.start, today.isBefore(month.end) ? today : month.end), 'this month (${_range(month)})'),
    };
  }

  static String answer(Map<String, Object?> args, FinanceSnapshot s, DateTime today) => switch (args['metric']) {
    'spent' => _total(args, s, today, TransactionType.expense),
    'earned' => _total(args, s, today, TransactionType.income),
    'owed' => _owed(args, s),
    'budget' => _budget(args, s),
    'goal' => _goals(args, s),
    'subscriptions' => _subscriptions(s, today),
    'loans' => _loans(s),
    _ => balance(s),
  };

  static String balance(FinanceSnapshot s) {
    final b = s.balance;
    final set = b.earmarked.isPositive ? ', after ${b.earmarked.format()} set aside for goals and your emergency fund' : '';
    return 'You have ${b.available.format()} available to spend (cash ${b.cash.format()}$set).';
  }

  static String _total(Map<String, Object?> args, FinanceSnapshot s, DateTime today, TransactionType type) {
    final (range, label) = period(args, s, today);
    final categoryName = args['category'] is String ? args['category'] as String : null;
    final category = categoryName == null ? null : findCategory(s, categoryName, type);
    final text = args['text'] is String ? (args['text'] as String).trim() : null;
    final person = args['person'] is String ? (args['person'] as String).trim() : null;
    final hits = s.transactions.where((t) {
      if (t.type != type || !range.contains(t.date)) return false;
      if (categoryName != null && t.categoryId != category?.id) return false;
      if (person != null && person.isNotEmpty && !(t.counterparty ?? '').toLowerCase().contains(person.toLowerCase())) {
        return false;
      }
      if (text != null && text.isNotEmpty) {
        final m = matchByName(text, [t], (x) => [x.note ?? '', x.counterparty ?? '', s.category(x.categoryId)?.name ?? '']);
        if (m is NoMatch) return false;
      }
      return true;
    }).toList();
    final total = Money.sum(hits.map((t) => t.amount));
    final verb = type == TransactionType.expense ? 'spent' : 'received';
    final on = category != null
        ? (type == TransactionType.expense ? ' on ${category.name}' : ' as ${category.name}')
        : (categoryName != null ? ' on "$categoryName"' : '');
    final about = [
      if (text != null && text.isNotEmpty) 'matching "$text"',
      if (person != null && person.isNotEmpty) 'with $person',
    ].join(' ');
    final count = hits.length == 1 ? '1 entry' : '${hits.length} entries';
    if (categoryName != null && category == null) return 'You have no "$categoryName" category.';
    return 'You $verb ${total.format()}$on${about.isEmpty ? '' : ' $about'} $label, across $count.';
  }

  static String _owed(Map<String, Object?> args, FinanceSnapshot s) {
    final open = s.pendingViews.where((v) => v.status.isActive).toList();
    final person = args['person'] is String ? (args['person'] as String).trim() : '';
    if (person.isNotEmpty) {
      final mine = open.where((v) => v.payment.counterparty.toLowerCase().contains(person.toLowerCase())).toList();
      if (mine.isEmpty) return 'Nothing is open with $person.';
      return [
        for (final v in mine.take(5))
          v.payment.direction == PendingDirection.owedToMe
              ? '${v.payment.counterparty} owes you ${v.outstanding.format()} for ${v.payment.purpose}.'
              : 'You owe ${v.payment.counterparty} ${v.outstanding.format()} for ${v.payment.purpose}.',
      ].join(' ');
    }
    final collect = open.where((v) => v.payment.direction == PendingDirection.owedToMe).toList();
    final pay = open.where((v) => v.payment.direction == PendingDirection.iOwe).toList();
    String people(List<PendingView> l) => l.take(3).map((v) => '${v.payment.counterparty} ${v.outstanding.format()}').join(', ');
    return [
      collect.isEmpty ? 'Nobody owes you money.' : 'People owe you ${s.pendingToCollect.format()} (${people(collect)}${collect.length > 3 ? '…' : ''}).',
      pay.isEmpty ? 'You owe nothing.' : 'You owe ${s.pendingToPay.format()} (${people(pay)}${pay.length > 3 ? '…' : ''}).',
    ].join(' ');
  }

  static String _budget(Map<String, Object?> args, FinanceSnapshot s) {
    final name = args['category'] is String ? args['category'] as String : null;
    final usages = s.budgetUsages;
    if (usages.isEmpty) return 'You have no budgets yet.';
    if (name != null) {
      final category = findCategory(s, name, TransactionType.expense);
      final u = usages.where((x) => x.budget.categoryId == category?.id).firstOrNull;
      if (u == null) return 'There is no budget for ${category?.name ?? name}.';
      final left = u.remaining.isNegative ? '${(-u.remaining).format()} over' : '${u.remaining.format()} left';
      return '${category!.name}: ${u.spent.format()} of ${u.budget.limit.format()} used this month, $left.';
    }
    final over = [for (final u in usages) if (u.isOver) s.category(u.budget.categoryId)?.name ?? ''];
    final near = [for (final u in usages) if (!u.isOver && u.health.name == 'warning') s.category(u.budget.categoryId)?.name ?? ''];
    return [
      'You have ${usages.length} budget${usages.length == 1 ? '' : 's'}.',
      if (over.isNotEmpty) 'Over the limit: ${over.join(', ')}.',
      if (near.isNotEmpty) 'Close to the limit: ${near.join(', ')}.',
      if (over.isEmpty && near.isEmpty) 'All are within their limits.',
    ].join(' ');
  }

  static String _goals(Map<String, Object?> args, FinanceSnapshot s) {
    final progress = s.goalProgress.where((g) => g.goal.status.name == 'active').toList();
    if (progress.isEmpty) return 'You have no active goals.';
    final query = [args['text'], args['category']].whereType<String>().firstOrNull;
    final list = query == null
        ? progress
        : switch (matchByName(query, progress, (g) => [g.goal.name])) {
            Matched(:final value) => [value],
            Ambiguous(:final candidates) => candidates,
            NoMatch() => progress,
          };
    return [
      for (final g in list.take(4)) '${g.goal.name}: ${g.saved.format()} of ${g.goal.target.format()} saved.',
    ].join(' ');
  }

  static String _subscriptions(FinanceSnapshot s, DateTime today) {
    final active = s.subscriptions.where((x) => x.isActive).toList();
    if (active.isEmpty) return 'You have no active subscriptions.';
    final soon = active.where((x) => !x.nextDueDate.isBefore(today) && daysBetween(today, x.nextDueDate) <= 7).toList();
    return [
      '${active.length} active subscription${active.length == 1 ? '' : 's'}, about ${s.monthlySubscriptionCommitment.format()} a month.',
      if (soon.isNotEmpty) 'Due this week: ${soon.map((x) => '${x.name} ${x.amount.format()} on ${_d(x.nextDueDate)}').join(', ')}.',
    ].join(' ');
  }

  static String _loans(FinanceSnapshot s) {
    final open = s.loanStates.where((l) => !l.isClosed).toList();
    if (open.isEmpty) return 'You have no open loans.';
    return [
      'You owe ${s.totalDebt.format()} on loans.',
      for (final l in open.take(3))
        if (l.nextDue case final next?) '${l.loan.name}: next ${next.payment.format()} on ${_d(next.dueDate)}.',
    ].join(' ');
  }
}
