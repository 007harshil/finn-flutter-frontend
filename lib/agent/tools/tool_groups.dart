import 'agent_tool.dart';
import 'json_schema.dart';

/// Tools are offered to the model in groups so each request stays small
/// (fewer tokens, better tool choice; providers advise roughly 10–15 tools
/// at most). The core group is always offered; other groups are switched on by
/// keywords in the user's message or by the model through `load_tools`, and
/// stay on for the rest of the conversation.
enum ToolGroup {
  core('lookups, income/expenses, pending payments'),
  // Not "transactions": models took that name to mean recording one, which
  // core already does, and spent a step loading it.
  edits('edit a transaction, new category'),
  budgets('create/change/pause budgets'),
  pending('split bill, write off'),
  loans('EMI/loan payments, new loan'),
  subscriptions('add, mark paid, pause/cancel, skip'),
  goals('create, contribute, withdraw'),
  emergencyFund('add/withdraw');

  const ToolGroup(this.summary);
  final String summary;
}

/// Which group each tool belongs to. Tools not listed are core.
const Map<String, ToolGroup> toolGroupOf = {
  'edit_transaction': ToolGroup.edits,
  'create_category': ToolGroup.edits,
  'create_budget': ToolGroup.budgets,
  'update_budget': ToolGroup.budgets,
  'pause_or_resume_budget': ToolGroup.budgets,
  'split_bill': ToolGroup.pending,
  'write_off_pending_payment': ToolGroup.pending,
  'record_loan_payment': ToolGroup.loans,
  'create_loan': ToolGroup.loans,
  'add_subscription': ToolGroup.subscriptions,
  'mark_subscription_paid': ToolGroup.subscriptions,
  'set_subscription_status': ToolGroup.subscriptions,
  'skip_subscription_cycle': ToolGroup.subscriptions,
  'create_goal': ToolGroup.goals,
  'contribute_to_goal': ToolGroup.goals,
  'withdraw_from_goal': ToolGroup.goals,
  'add_to_emergency_fund': ToolGroup.emergencyFund,
  'withdraw_from_emergency_fund': ToolGroup.emergencyFund,
};

final Map<ToolGroup, RegExp> _keywords = {
  ToolGroup.edits: RegExp(r'\b(edit|change|correct|wrong|fix|update|categor\w*)\b', caseSensitive: false),
  ToolGroup.budgets: RegExp(r'\bbudget\w*\b|\blimit\b', caseSensitive: false),
  ToolGroup.pending: RegExp(r'\b(split\w*|share|shared|write.?off|forgive|won.?t pay)\b', caseSensitive: false),
  ToolGroup.loans: RegExp(r'\b(emi|loan\w*|instal+ment\w*|prepay\w*|mortgage)\b', caseSensitive: false),
  ToolGroup.subscriptions: RegExp(
    r'\b(subscri\w*|renew\w*|netflix|spotify|prime|hotstar|youtube|membership|plan)\b',
    caseSensitive: false,
  ),
  ToolGroup.goals: RegExp(r'\b(goal\w*|saving for|save for|towards)\b', caseSensitive: false),
  ToolGroup.emergencyFund: RegExp(r'\bemergency\b', caseSensitive: false),
};

/// The groups switched on for one conversation.
class ToolSelection {
  final Set<ToolGroup> _enabled = {ToolGroup.core};

  Set<ToolGroup> get enabled => Set.unmodifiable(_enabled);

  void enable(Iterable<ToolGroup> groups) => _enabled.addAll(groups);

  /// Switches on groups whose keywords appear in [text].
  void enableFor(String text) {
    for (final e in _keywords.entries) {
      if (e.value.hasMatch(text)) _enabled.add(e.key);
    }
  }

  /// The tools to offer now, in toolbox order.
  List<AgentTool> offered(List<AgentTool> all) => [
    for (final t in all)
      if (_enabled.contains(toolGroupOf[t.name] ?? ToolGroup.core)) t,
  ];
}

/// Lets the model switch on more tool groups when the request needs them.
class LoadToolsTool extends ReadTool {
  const LoadToolsTool();

  @override
  String get name => 'load_tools';

  @override
  String get progressLabel => 'Getting ready';

  @override
  String get description =>
      'Adds tool groups from your next step (recording income/expenses is always available): '
      '${[for (final g in ToolGroup.values)
        if (g != ToolGroup.core) '${g.name} (${g.summary})'].join('; ')}.';

  @override
  Map<String, Object?> get parameters => JsonSchema.object(
    {
      'groups': {
        'type': 'array',
        'items': {
          'type': 'string',
          'enum': [
            for (final g in ToolGroup.values)
              if (g != ToolGroup.core) g.name,
          ],
        },
      },
    },
    required: ['groups'],
  );

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args, ToolContext context) async {
    final raw = args['groups'];
    final groups = <ToolGroup>[
      if (raw is List)
        for (final v in raw) ...ToolGroup.values.where((g) => g.name == v && g != ToolGroup.core),
    ];
    context.selection?.enable(groups);
    return {
      'loaded': [for (final g in groups) g.name],
      'tools': [
        for (final e in toolGroupOf.entries)
          if (groups.contains(e.value)) e.key,
      ],
    };
  }
}
