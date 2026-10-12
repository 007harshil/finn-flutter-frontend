import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../actions/action.dart';
import '../../core/result/result.dart';
import '../../finance/finance_snapshot.dart';
import '../llm/llm_types.dart';
import 'json_schema.dart';
import 'tool_groups.dart';

/// A capability the model can call. Three kinds exist:
/// * [ReadTool]: looks up data the user is authorised to see and runs
///   immediately.
/// * [ActionTool]: proposes a registered [FinancialAction]. It is executed by
///   the `ToolExecutor` through the action dispatcher only after the user
///   approves the preview.
/// * [QueueActionsTool]: proposes several [ActionTool] calls in one model
///   step, each validated exactly like a direct call.
sealed class AgentTool {
  const AgentTool();

  /// Function name shown to the model (`^[a-zA-Z0-9_-]{1,64}$`).
  String get name;
  String get description;

  /// JSON Schema of the arguments (root type `object`).
  Map<String, Object?> get parameters;

  /// Short progress text shown while the tool runs.
  String get progressLabel;

  LlmToolSpec get spec => LlmToolSpec(name: name, description: description, parameters: parameters);
}

/// What a read tool can access: a fresh snapshot built from data the app
/// already holds for the signed-in user (synced from the FiNN API in remote
/// mode). Read tools never write and never see credentials.
class ToolContext {
  const ToolContext({required this.loadSnapshot, this.selection});
  final Future<FinanceSnapshot> Function() loadSnapshot;

  /// Tool groups offered in this conversation (see `tool_groups.dart`).
  final ToolSelection? selection;
}

abstract class ReadTool extends AgentTool {
  const ReadTool();

  /// Runs the lookup. Throw [AppFailure] for expected problems (bad filter).
  Future<Map<String, Object?>> run(Map<String, Object?> args, ToolContext context);
}

/// Exposes one registered action as a tool.
class ActionTool extends AgentTool {
  const ActionTool({
    required this.name,
    required this.action,
    this.guidance,
    this.fieldOverrides = const {},
    this.excludedFields = const {},
  });

  @override
  final String name;
  final FinancialAction<ActionInput, Object?> action;

  /// Extra instructions appended to the action's own description.
  final String? guidance;

  /// Schema replacements for fields whose spec is too coarse.
  final Map<String, Map<String, Object?>> fieldOverrides;

  /// Optional fields hidden from the model (and dropped if it sends them).
  final Set<String> excludedFields;

  ActionDescriptor get descriptor => action.descriptor;

  @override
  String get progressLabel => 'Preparing: ${descriptor.title.toLowerCase()}';

  /// Kept short to save tokens; rules shared by all actions (approval,
  /// ids, dates) are in the instructions.
  @override
  String get description => ['${descriptor.title}. ${descriptor.description}', ?guidance].join(' ');

  @override
  Map<String, Object?> get parameters => _schemas[name] ??= JsonSchema.forAction(descriptor, overrides: fieldOverrides, exclude: excludedFields);

  static final Map<String, Map<String, Object?>> _schemas = {};
}

/// Queues many actions in a single tool call.
///
/// Models without parallel tool calls (gpt-oss) otherwise need one model
/// round trip per action, and every round trip resends the whole request:
/// a four-item message took ten calls and ~15k tokens, far over free-tier
/// per-minute limits. With this tool the same message is one call. With
/// [doneField] set, the runner opens the review card straight away instead
/// of asking the model for a closing sentence.
final class QueueActionsTool extends AgentTool {
  const QueueActionsTool(this.actionToolNames);

  static const toolName = 'queue_actions';
  static const doneField = 'done';

  /// Upper bound on actions in one call (runaway protection).
  static const maxActions = 12;

  /// Every action tool the model may name in an item.
  final List<String> actionToolNames;

  @override
  String get name => toolName;

  @override
  String get progressLabel => 'Preparing your changes';

  @override
  String get description => 'Queue one or more actions for review in ONE call (preferred over calling action tools '
      'one at a time). Each item names an action tool and gives exactly the arguments that tool takes.';

  @override
  Map<String, Object?> get parameters => JsonSchema.object({
        'actions': {
          'type': 'array',
          'minItems': 1,
          'maxItems': maxActions,
          'items': JsonSchema.object({
            'tool': JsonSchema.string('Action tool name', values: actionToolNames),
            'arguments': {'type': 'object', 'description': "That tool's arguments"},
          }, required: ['tool', 'arguments']),
        },
        doneField: JsonSchema.boolean(
            'true when these are all the changes left for this request (nothing more to look up, ask or wait for); '
            'the user then reviews them and you are finished'),
      }, required: ['actions', doneField]);
}

/// Uniform JSON returned to the model for every tool call.
@immutable
class ToolResult {
  const ToolResult._(this.json, {required this.ok});

  factory ToolResult.data(Map<String, Object?> data) => ToolResult._({'ok': true, ...data}, ok: true);

  factory ToolResult.error(String code, String message, {Map<String, String> fields = const {}, String? hint}) =>
      ToolResult._({
        'ok': false,
        'error': {
          'code': code,
          'message': message,
          if (fields.isNotEmpty) 'fields': fields,
          'hint': ?hint,
        },
      }, ok: false);

  factory ToolResult.failure(AppFailure f, {String? hint}) =>
      ToolResult.error(f.code.name, f.message, fields: f.fieldErrors, hint: hint);

  /// Result of a [QueueActionsTool] call; [ok] only when every item was.
  factory ToolResult.batch(Map<String, Object?> data, {required bool ok}) => ToolResult._({'ok': ok, ...data}, ok: ok);

  final Map<String, Object?> json;
  final bool ok;

  /// Encoded for the model, truncated to keep requests small.
  String encode({int maxChars = 3000}) {
    final text = jsonEncode(json);
    if (text.length <= maxChars) return text;
    final shortened = jsonEncode({
      ...json.map((k, v) => MapEntry(k, v is List && v.length > 5 ? v.take(5).toList() : v)),
      'truncated': 'Only part of the result is shown. Narrow the search for more.',
    });
    if (shortened.length <= maxChars) return shortened;
    return jsonEncode({'ok': ok, 'truncated': 'The result was too large. Narrow the search.'});
  }
}
