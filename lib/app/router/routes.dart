import '../../core/time/dates.dart';
import '../../features/transactions/domain/transaction.dart';

/// Every navigable location. Use these builders instead of string literals.
///
/// Detail and list screens live inside the bottom-navigation branches;
/// forms and quick actions open as modal sheets on the root navigator but
/// still have URLs, so they are deep-linkable (e.g. `finn://app/more/loans/x/pay`).
abstract final class AppRoutes {
  static const onboarding = '/onboarding';

  // Authentication (outside the shell; every other route requires sign-in)
  static const login = '/login';
  static const verifyOtpPath = '/login/verify';
  static String loginWithEmail(String email) => '$login?email=${Uri.encodeQueryComponent(email)}';
  static String verifyOtp(String email) => '$verifyOtpPath?email=${Uri.encodeQueryComponent(email)}';

  // Home branch
  static const home = '/home';
  static const alerts = '/home/alerts';
  static const timeline = '/home/timeline';

  // Transactions branch
  static const transactions = '/transactions';
  static String transactionsFiltered({TransactionType? type, MonthKey? month}) {
    final q = <String>[
      if (type != null) 'type=${type.name}',
      if (month != null) 'month=${month.id}',
    ];
    return q.isEmpty ? transactions : '$transactions?${q.join('&')}';
  }

  static String newTransaction({TransactionType type = TransactionType.expense}) =>
      '/transactions/new?type=${type.name}';
  static String transaction(String id) => '/transactions/$id';
  static String editTransaction(String id) => '/transactions/$id/edit';

  // Budgets branch
  static const budgets = '/budgets';
  static const newBudget = '/budgets/new';
  /// A budget; [month] opens a past month read-only.
  static String budget(String id, {MonthKey? month}) =>
      month == null ? '/budgets/$id' : '/budgets/$id?month=${month.id}';
  static String editBudget(String id) => '/budgets/$id/edit';

  // Goals branch (includes the emergency fund)
  static const goals = '/goals';
  static const newGoal = '/goals/new';
  static String goal(String id) => '/goals/$id';
  static String editGoal(String id) => '/goals/$id/edit';
  static String goalContribute(String id) => '/goals/$id/move?kind=contribute';
  static String goalWithdraw(String id) => '/goals/$id/move?kind=withdraw';
  static const emergencyFund = '/goals/emergency-fund';
  static const emergencyPlan = '/goals/emergency-fund/plan';
  static const emergencyContribute = '/goals/emergency-fund/move?kind=contribute';
  static const emergencyWithdraw = '/goals/emergency-fund/move?kind=withdraw';

  // More branch
  static const more = '/more';
  static const account = '/more/account';
  static const loans = '/more/loans';
  static const newLoan = '/more/loans/new';
  static String loan(String id) => '/more/loans/$id';
  static String editLoan(String id) => '/more/loans/$id/edit';
  static String payLoan(String id) => '/more/loans/$id/pay';

  static const subscriptions = '/more/subscriptions';
  static const newSubscription = '/more/subscriptions/new';
  static String subscription(String id) => '/more/subscriptions/$id';
  static String editSubscription(String id) => '/more/subscriptions/$id/edit';

  static const pending = '/more/pending';
  static String newPending({bool owedToMe = false}) => '/more/pending/new${owedToMe ? '?direction=owedToMe' : ''}';
  static String pendingItem(String id) => '/more/pending/$id';
  static String editPending(String id) => '/more/pending/$id/edit';
  static String settlePending(String id) => '/more/pending/$id/settle';

  static const analytics = '/more/analytics';
  static const netWorth = '/more/net-worth';
  static const newAsset = '/more/net-worth/assets/new';
  static String editAsset(String id) => '/more/net-worth/assets/$id/edit';

  static const settings = '/more/settings';
  static const profile = '/more/settings/profile';
  static const categories = '/more/settings/categories';
  static String newCategory({TransactionType type = TransactionType.expense}) =>
      '/more/settings/categories/new?type=${type.name}';
  static String editCategory(String id) => '/more/settings/categories/$id/edit';
  static const export = '/more/settings/export';
  static const notifications = '/more/settings/notifications';
  static const activity = '/more/settings/activity';
}
