import 'package:flutter/foundation.dart';

import '../../app/router/routes.dart';
import '../../features/goals/domain/goal.dart';
import '../../features/subscriptions/domain/subscription.dart';
import '../../finance/finance_snapshot.dart';
import '../plan/resolvers.dart';

/// A place in the app the agent can take the user. Opening a page changes
/// nothing, so it needs no review.
@immutable
class AgentNavigation {
  const AgentNavigation({required this.route, required this.label});

  /// Always built here from [agentPages] or a record id, never from model text.
  final String route;

  /// What the "Open …" button says ("Loans & EMIs", "Japan trip").
  final String label;
}

/// Pages the agent may open: a fixed allowlist. The model names a key; the
/// route is the app's own.
const agentPages = <String, ({String label, String route})>{
  'home': (label: 'Home', route: AppRoutes.home),
  'activity': (label: 'Activity', route: AppRoutes.transactions),
  'budgets': (label: 'Budgets', route: AppRoutes.budgets),
  'goals': (label: 'Goals', route: AppRoutes.goals),
  'emergency_fund': (label: 'Emergency fund', route: AppRoutes.emergencyFund),
  'loans': (label: 'Loans & EMIs', route: AppRoutes.loans),
  'subscriptions': (label: 'Subscriptions', route: AppRoutes.subscriptions),
  'pending': (label: 'Pending payments', route: AppRoutes.pending),
  'accounts': (label: 'Accounts', route: AppRoutes.accounts),
  'categories': (label: 'Categories', route: AppRoutes.categories),
  'insights': (label: 'Insights', route: AppRoutes.analytics),
  'net_worth': (label: 'Net worth', route: AppRoutes.netWorth),
  'export': (label: 'Export', route: AppRoutes.export),
  'settings': (label: 'Settings', route: AppRoutes.settings),
  'friends': (label: 'Friends', route: AppRoutes.friends),
  'alerts': (label: 'Alerts', route: AppRoutes.alerts),
  'profile': (label: 'Profile', route: AppRoutes.profile),
};

/// Words people use for a page (lower case), besides its key.
const _pageWords = <String, String>{
  'dashboard': 'home',
  'home screen': 'home',
  'transactions': 'activity',
  'expenses': 'activity',
  'budget': 'budgets',
  'goal': 'goals',
  'savings goals': 'goals',
  'emergency fund': 'emergency_fund',
  'loan': 'loans',
  'emi': 'loans',
  'emis': 'loans',
  'loans & emis': 'loans',
  'loans and emis': 'loans',
  'subscription': 'subscriptions',
  'pending payments': 'pending',
  'debts': 'pending',
  'udhaar': 'pending',
  'account': 'accounts',
  'category': 'categories',
  'analytics': 'insights',
  'reports': 'insights',
  'net worth': 'net_worth',
  'networth': 'net_worth',
  'setting': 'settings',
  'friend': 'friends',
  'notifications': 'alerts',
  'my profile': 'profile',
};

abstract final class AgentPages {
  /// The page key for what someone called a page ("Loans & EMIs", "emi",
  /// "net-worth"), or null when it is not one of [agentPages].
  static String? keyOf(String? raw) {
    if (raw == null) return null;
    final t = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]'), ' ')
        .replaceAll(RegExp(r'\s+(page|screen|tab|section)$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final key = t.replaceAll(' ', '_');
    if (agentPages.containsKey(key)) return key;
    return _pageWords[t];
  }

  static AgentNavigation? page(String? raw) {
    final key = keyOf(raw);
    final p = key == null ? null : agentPages[key];
    return p == null ? null : AgentNavigation(route: p.route, label: p.label);
  }

  /// [page], or one record on it when [name] matches exactly one ("Japan
  /// trip" on goals). An unclear name never asks: it opens the page, with a
  /// [note] when nothing matched.
  static ({AgentNavigation nav, String? note})? resolve(String? page, String? name, FinanceSnapshot s) {
    final key = keyOf(page);
    final base = AgentPages.page(key);
    if (key == null || base == null) return null;
    final query = name?.trim();
    if (query == null || query.isEmpty) return (nav: base, note: null);

    AgentNavigation? record;
    var known = true;
    void pick<T>(Iterable<T> items, Iterable<String> Function(T) labels, String Function(T) route, String Function(T) label) {
      final m = matchByName(query, items, labels);
      if (m is Matched<T>) record = AgentNavigation(route: route(m.value), label: label(m.value));
      if (m is NoMatch<T>) known = false;
    }

    switch (key) {
      case 'goals':
        pick(s.goals.where((g) => g.status == GoalStatus.active), (g) => [g.name], (g) => AppRoutes.goal(g.id), (g) => g.name);
      case 'loans':
        pick(
          s.loanStates.where((l) => !l.isClosed),
          (l) => [l.loan.name, l.loan.counterparty],
          (l) => AppRoutes.loan(l.loan.id),
          (l) => l.loan.name,
        );
      case 'subscriptions':
        pick(
          s.subscriptions.where((x) => x.status != SubscriptionStatus.cancelled),
          (x) => [x.name],
          (x) => AppRoutes.subscription(x.id),
          (x) => x.name,
        );
      case 'pending':
        pick(
          s.pendingViews.where((v) => v.status.isActive),
          (v) => [v.payment.counterparty],
          (v) => AppRoutes.pendingItem(v.payment.id),
          (v) => v.payment.counterparty,
        );
      case 'accounts':
        pick(s.activeAccounts, (a) => [a.name], (a) => AppRoutes.accountDetail(a.id), (a) => a.name);
      case 'budgets':
        pick(
          s.budgets,
          (b) => [s.category(b.categoryId)?.name ?? ''],
          (b) => AppRoutes.budget(b.id),
          (b) => '${s.category(b.categoryId)?.name ?? 'Budget'} budget',
        );
      default:
        return (nav: base, note: null);
    }
    if (record case final r?) return (nav: r, note: null);
    return (nav: base, note: known ? null : 'I couldn\'t find "$query", so here is ${base.label}.');
  }
}
