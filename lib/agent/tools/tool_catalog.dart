import '../../actions/action.dart';
import '../../actions/action_registry.dart';
import 'agent_tool.dart';
import 'json_schema.dart';
import 'read_tools.dart';
import 'tool_groups.dart';

/// Which registered actions the agent may propose, under which tool name.
///
/// This allowlist is the agent's permission boundary on top of the action
/// policy: deletes are never listed (the policy forbids them for the agent
/// channel anyway), nor are profile or asset edits. To expose another
/// action, add one entry here; schema, validation, preview and execution
/// come from the action itself.
const Map<String, ({String actionId, String? guidance})> agentActionTools = {
  'record_transaction': (
    actionId: 'transactions.create',
    guidance: null,
  ),
  'edit_transaction': (
    actionId: 'transactions.update',
    guidance: 'Find the transaction with search_transactions first and send every field (changed and unchanged) '
        'with its version as expectedVersion. Linked transactions cannot be edited.',
  ),
  'create_category': (actionId: 'categories.create', guidance: 'Only when no existing category fits.'),
  'create_budget': (actionId: 'budgets.create', guidance: null),
  'update_budget': (
    actionId: 'budgets.update',
    guidance: 'Send all fields with the budget version from find_records as expectedVersion.',
  ),
  'pause_or_resume_budget': (actionId: 'budgets.setPaused', guidance: null),
  'add_pending_payment': (
    actionId: 'pending.create',
    guidance: null,
  ),
  'split_bill': (actionId: 'pending.split', guidance: null),
  'settle_pending_payment': (
    actionId: 'pending.settle',
    guidance: 'Get pendingId from find_records(kind: pending).',
  ),
  'write_off_pending_payment': (actionId: 'pending.cancel', guidance: 'Only when the user says it will not be paid.'),
  'record_loan_payment': (actionId: 'loans.recordPayment', guidance: 'Resolve loanId with find_records(kind: loans).'),
  'create_loan': (actionId: 'loans.create', guidance: null),
  'add_subscription': (actionId: 'subscriptions.create', guidance: null),
  'mark_subscription_paid': (
    actionId: 'subscriptions.markPaid',
    guidance: 'Resolve subscriptionId with find_records(kind: subscriptions).',
  ),
  'set_subscription_status': (actionId: 'subscriptions.setStatus', guidance: null),
  'skip_subscription_cycle': (actionId: 'subscriptions.skipCycle', guidance: null),
  'create_goal': (actionId: 'goals.create', guidance: null),
  'contribute_to_goal': (
    actionId: 'goals.contribute',
    guidance: 'Earmarks available money for a goal. Resolve goalId with find_records(kind: goals).',
  ),
  'withdraw_from_goal': (actionId: 'goals.withdraw', guidance: null),
  'add_to_emergency_fund': (actionId: 'emergencyFund.contribute', guidance: null),
  'withdraw_from_emergency_fund': (actionId: 'emergencyFund.withdraw', guidance: null),
};

const _paymentMethods = ['upi', 'card', 'cash', 'bankTransfer', 'wallet', 'other'];

/// Schema fixes for fields whose descriptor spec is too coarse for a model.
final Map<String, Map<String, Map<String, Object?>>> _fieldOverrides = {
  'pending.split': {
    'people': {
      'type': 'array',
      'description': 'The other people (not the user), 2 or more',
      'minItems': 1,
      'maxItems': 20,
      'items': JsonSchema.object({
        'counterparty': JsonSchema.string('Person name', maxLength: 80),
        'value': {
          'type': 'number',
          'description': 'Their value for exact (rupees), percent (%), shares (parts) or adjustment (rupees ±); '
              'omit for equally',
        },
      }, required: ['counterparty']),
    },
    'myValue': {'type': 'number', 'description': 'Your own value when includeMe, same unit as people[].value'},
  },
  'loans.recordPayment': {'method': JsonSchema.string('Payment method', values: _paymentMethods)},
};

/// Fields the agent may not set. Sharing a pending item with another FiNN
/// user needs a people-directory lookup the agent does not have, so agent
/// created items stay private.
const Map<String, Set<String>> _excludedFields = {
  'pending.create': {'linkedUserId'},
};

/// The tools the agent is given, built from the action registry.
class AgentToolbox {
  AgentToolbox(this.tools) : _byName = {for (final t in tools) t.name: t} {
    if (_byName.length != tools.length) throw StateError('Duplicate agent tool name');
  }

  /// Read tools plus every allowlisted action found in [registry].
  factory AgentToolbox.standard(ActionRegistry registry) {
    final actionTools = <AgentTool>[];
    for (final entry in agentActionTools.entries) {
      final action = registry.lookup(entry.value.actionId);
      if (action == null) continue;
      actionTools.add(ActionTool(
        name: entry.key,
        action: action,
        guidance: entry.value.guidance,
        fieldOverrides: _fieldOverrides[entry.value.actionId] ?? const {},
        excludedFields: _excludedFields[entry.value.actionId] ?? const {},
      ));
    }
    return AgentToolbox([
      const FinancialOverviewTool(),
      const FindRecordsTool(),
      const SearchTransactionsTool(),
      const LoadToolsTool(),
      ...actionTools,
    ]);
  }

  final List<AgentTool> tools;
  final Map<String, AgentTool> _byName;

  AgentTool? lookup(String name) => _byName[name];

  /// Action tool for [actionId], if exposed.
  ActionTool? forAction(String actionId) =>
      tools.whereType<ActionTool>().where((t) => t.descriptor.id == actionId).firstOrNull;

  bool exposesAction(ActionDescriptor d) => forAction(d.id) != null;
}
