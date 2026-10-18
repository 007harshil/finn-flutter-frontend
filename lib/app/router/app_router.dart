import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../agent/agent.dart' show AgentScreen;
import '../../core/time/dates.dart';
import '../../features/alerts/presentation/alerts_screen.dart';
import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/verify_otp_screen.dart';
import '../../features/budgets/presentation/budget_detail_screen.dart';
import '../../features/accounts/presentation/account_detail_screen.dart';
import '../../features/accounts/presentation/account_form_sheet.dart';
import '../../features/accounts/presentation/accounts_screen.dart';
import '../../features/accounts/presentation/set_balance_sheet.dart';
import '../../features/budgets/presentation/budget_form_sheet.dart';
import '../../features/budgets/presentation/budgets_screen.dart';
import '../../features/categories/presentation/categories_screen.dart';
import '../../features/categories/presentation/category_form_sheet.dart';
import '../../features/emergency_fund/presentation/emergency_fund_screen.dart';
import '../../features/emergency_fund/presentation/emergency_movement_sheet.dart';
import '../../features/emergency_fund/presentation/emergency_plan_sheet.dart';
import '../../features/export/presentation/export_screen.dart';
import '../../features/goals/presentation/goal_detail_screen.dart';
import '../../features/goals/presentation/goal_form_sheet.dart';
import '../../features/goals/presentation/goal_movement_sheet.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/loans/presentation/loan_detail_screen.dart';
import '../../features/loans/presentation/loan_form_sheet.dart';
import '../../features/loans/presentation/loan_payment_sheet.dart';
import '../../features/loans/presentation/loans_screen.dart';
import '../../features/friends/presentation/friends_screen.dart';
import '../../features/more/presentation/more_screen.dart';
import '../../features/net_worth/presentation/asset_form_sheet.dart';
import '../../features/net_worth/presentation/net_worth_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/pending/presentation/pending_detail_screen.dart';
import '../../features/pending/presentation/pending_form_sheet.dart';
import '../../features/pending/presentation/pending_screen.dart';
import '../../features/pending/presentation/settle_pending_sheet.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/settings/presentation/activity_log_screen.dart';
import '../../features/settings/presentation/notification_settings_screen.dart';
import '../../features/settings/presentation/profile_sheet.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/subscriptions/presentation/subscription_detail_screen.dart';
import '../../features/subscriptions/presentation/subscription_form_sheet.dart';
import '../../features/subscriptions/presentation/subscriptions_screen.dart';
import '../../features/timeline/presentation/timeline_screen.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../features/transactions/presentation/transaction_detail_screen.dart';
import '../../features/transactions/presentation/transaction_form_sheet.dart';
import '../../features/transactions/presentation/transactions_screen.dart';
import '../di/core_providers.dart';
import '../shell/app_shell.dart';
import 'routes.dart';
import 'sheet_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Builds the app router. Redirects to sign-in until signed in, then to
/// onboarding until it is completed.
final routerProvider = Provider<GoRouter>((ref) {
  final onboarded = ValueNotifier<bool>(ref.read(settingsProvider).onboardingComplete);
  ref.listen(settingsProvider.select((s) => s.onboardingComplete), (_, v) => onboarded.value = v);
  ref.onDispose(onboarded.dispose);
  final signedIn = ValueNotifier<bool>(ref.read(authControllerProvider) != null);
  ref.listen(authControllerProvider.select((s) => s != null), (_, v) => signedIn.value = v);
  ref.onDispose(signedIn.dispose);

  GoRoute sheet(String path, Widget Function(GoRouterState s) build) => GoRoute(
    path: path,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) => SheetPage<Object?>(key: state.pageKey, child: build(state)),
  );

  GoRoute page(String path, Widget Function(GoRouterState s) build, {List<RouteBase> routes = const []}) => GoRoute(
    path: path,
    pageBuilder: (context, state) => FadeScalePage<Object?>(key: state.pageKey, child: build(state)),
    routes: routes,
  );

  TransactionType? typeParam(GoRouterState s) =>
      TransactionType.values.where((t) => t.name == s.uri.queryParameters['type']).firstOrNull;

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,
    refreshListenable: Listenable.merge([onboarded, signedIn]),
    redirect: (context, state) {
      final atAuth = state.matchedLocation == AppRoutes.login || state.matchedLocation == AppRoutes.verifyOtpPath;
      if (!signedIn.value) return atAuth ? null : AppRoutes.login;
      if (atAuth) return onboarded.value ? AppRoutes.home : AppRoutes.onboarding;
      final atOnboarding = state.matchedLocation == AppRoutes.onboarding;
      if (!onboarded.value && !atOnboarding) return AppRoutes.onboarding;
      if (onboarded.value && atOnboarding) return AppRoutes.home;
      return null;
    },
    errorBuilder: (context, state) => const _NotFoundScreen(),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => AppRoutes.home),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, s) => LoginScreen(initialEmail: s.uri.queryParameters['email']),
        routes: [
          GoRoute(
            path: 'verify',
            redirect: (_, s) => (s.uri.queryParameters['email'] ?? '').isEmpty ? AppRoutes.login : null,
            builder: (_, s) => VerifyOtpScreen(email: s.uri.queryParameters['email']!),
          ),
        ],
      ),
      GoRoute(path: AppRoutes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: AppRoutes.assistant,
        pageBuilder: (context, state) => FadeScalePage<Object?>(key: state.pageKey, child: const AgentScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (_, _) => const HomeScreen(),
                routes: [page('alerts', (_) => const AlertsScreen()), page('timeline', (_) => const TimelineScreen())],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.transactions,
                builder: (_, s) => TransactionsScreen(
                  initialType: typeParam(s),
                  initialMonth: MonthKey.tryParse(s.uri.queryParameters['month']),
                ),
                routes: [
                  sheet('new', (s) => TransactionFormSheet(initialType: typeParam(s) ?? TransactionType.expense)),
                  page(
                    ':txId',
                    (s) => TransactionDetailScreen(id: s.pathParameters['txId']!),
                    routes: [sheet('edit', (s) => TransactionFormSheet(transactionId: s.pathParameters['txId']))],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.budgets,
                builder: (_, _) => const BudgetsScreen(),
                routes: [
                  sheet('new', (_) => const BudgetFormSheet()),
                  page(
                    ':budgetId',
                    (s) => BudgetDetailScreen(
                      id: s.pathParameters['budgetId']!,
                      month: MonthKey.tryParse(s.uri.queryParameters['month']),
                    ),
                    routes: [sheet('edit', (s) => BudgetFormSheet(budgetId: s.pathParameters['budgetId']))],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.goals,
                builder: (_, _) => const GoalsScreen(),
                routes: [
                  sheet('new', (_) => const GoalFormSheet()),
                  page(
                    'emergency-fund',
                    (_) => const EmergencyFundScreen(),
                    routes: [
                      sheet('plan', (_) => const EmergencyPlanSheet()),
                      sheet(
                        'move',
                        (s) => EmergencyMovementSheet(withdraw: s.uri.queryParameters['kind'] == 'withdraw'),
                      ),
                    ],
                  ),
                  page(
                    ':goalId',
                    (s) => GoalDetailScreen(id: s.pathParameters['goalId']!),
                    routes: [
                      sheet('edit', (s) => GoalFormSheet(goalId: s.pathParameters['goalId'])),
                      sheet(
                        'move',
                        (s) => GoalMovementSheet(
                          goalId: s.pathParameters['goalId']!,
                          withdraw: s.uri.queryParameters['kind'] == 'withdraw',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.more,
                builder: (_, _) => const MoreScreen(),
                routes: [
                  page('account', (_) => const ProfileScreen()),
                  page('friends', (_) => const FriendsScreen()),
                  page(
                    'loans',
                    (_) => const LoansScreen(),
                    routes: [
                      sheet('new', (_) => const LoanFormSheet()),
                      page(
                        ':loanId',
                        (s) => LoanDetailScreen(id: s.pathParameters['loanId']!),
                        routes: [
                          sheet('edit', (s) => LoanFormSheet(loanId: s.pathParameters['loanId'])),
                          sheet('pay', (s) => LoanPaymentSheet(loanId: s.pathParameters['loanId']!)),
                        ],
                      ),
                    ],
                  ),
                  page(
                    'subscriptions',
                    (_) => const SubscriptionsScreen(),
                    routes: [
                      sheet('new', (_) => const SubscriptionFormSheet()),
                      page(
                        ':subId',
                        (s) => SubscriptionDetailScreen(id: s.pathParameters['subId']!),
                        routes: [
                          sheet('edit', (s) => SubscriptionFormSheet(subscriptionId: s.pathParameters['subId'])),
                        ],
                      ),
                    ],
                  ),
                  page(
                    'pending',
                    (_) => const PendingScreen(),
                    routes: [
                      sheet('new', (s) => PendingFormSheet(owedToMe: s.uri.queryParameters['direction'] == 'owedToMe')),
                      page(
                        ':pendingId',
                        (s) => PendingDetailScreen(id: s.pathParameters['pendingId']!),
                        routes: [
                          sheet('edit', (s) => PendingFormSheet(pendingId: s.pathParameters['pendingId'])),
                          sheet('settle', (s) => SettlePendingSheet(pendingId: s.pathParameters['pendingId']!)),
                        ],
                      ),
                    ],
                  ),
                  page(
                    'accounts',
                    (_) => const AccountsScreen(),
                    routes: [
                      sheet('new', (_) => const AccountFormSheet()),
                      page(
                        ':accountId',
                        (s) => AccountDetailScreen(id: s.pathParameters['accountId']!),
                        routes: [
                          sheet('edit', (s) => AccountFormSheet(accountId: s.pathParameters['accountId'])),
                          sheet('balance', (s) => SetBalanceSheet(accountId: s.pathParameters['accountId']!)),
                        ],
                      ),
                    ],
                  ),
                  page('analytics', (_) => const AnalyticsScreen()),
                  page(
                    'net-worth',
                    (_) => const NetWorthScreen(),
                    routes: [
                      sheet('assets/new', (_) => const AssetFormSheet()),
                      sheet('assets/:assetId/edit', (s) => AssetFormSheet(assetId: s.pathParameters['assetId'])),
                    ],
                  ),
                  page(
                    'settings',
                    (_) => const SettingsScreen(),
                    routes: [
                      sheet('profile', (_) => const ProfileSheet()),
                      page(
                        'categories',
                        (_) => const CategoriesScreen(),
                        routes: [
                          sheet('new', (s) => CategoryFormSheet(initialType: typeParam(s) ?? TransactionType.expense)),
                          sheet(
                            ':categoryId/edit',
                            (s) => CategoryFormSheet(categoryId: s.pathParameters['categoryId']),
                          ),
                        ],
                      ),
                      page('export', (_) => const ExportScreen()),
                      page('notifications', (_) => const NotificationSettingsScreen()),
                      page('activity', (_) => const ActivityLogScreen()),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('404', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 8),
          const Text('This page does not exist.'),
          TextButton(onPressed: () => context.go(AppRoutes.home), child: const Text('Return to Home')),
        ],
      ),
    ),
  );
}
