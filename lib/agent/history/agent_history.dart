import 'package:flutter/foundation.dart';

import '../../core/result/result.dart';
import '../../data/remote/api_client.dart';

/// Agent history: what the user asked the agent to do and what actually
/// happened, one entry per turn that proposed changes. Stored by the FiNN
/// API from its own step outcomes (`POST /plans/execute` with `history`),
/// read with `GET /agent/history`. It is for the user's review only and is
/// never sent to the model; questions about it are answered by
/// [historyAnswer] without a model call.

enum AgentRunStatus {
  completed('Saved'),
  partial('Partly saved'),
  failed('Not saved'),
  declined('Declined');

  const AgentRunStatus(this.label);
  final String label;

  static AgentRunStatus parse(Object? v) => values.where((s) => s.name == v).firstOrNull ?? AgentRunStatus.failed;
}

/// Outcome of one operation: `saved`, `alreadySaved`, `declined`, `failed`,
/// `skipped` (its dependency was not saved) or `changed` (the record changed
/// after review).
@immutable
class AgentHistoryOperation {
  const AgentHistoryOperation({
    required this.ref,
    required this.actionId,
    required this.summary,
    required this.status,
    this.recordIds = const [],
    this.message,
  });

  factory AgentHistoryOperation.fromJson(Map<String, Object?> j) => AgentHistoryOperation(
    ref: j['ref']?.toString() ?? '',
    actionId: j['actionId']?.toString() ?? '',
    summary: j['summary']?.toString() ?? '',
    status: j['status']?.toString() ?? 'failed',
    recordIds: [for (final id in (j['recordIds'] as List? ?? const [])) id.toString()],
    message: j['message'] as String?,
  );

  final String ref;
  final String actionId;
  final String summary;
  final String status;
  final List<String> recordIds;
  final String? message;

  bool get saved => status == 'saved' || status == 'alreadySaved';
}

@immutable
class AgentHistoryEntry {
  const AgentHistoryEntry({
    required this.id,
    required this.request,
    required this.status,
    required this.summary,
    required this.createdAt,
    this.operations = const [],
    this.notes = const [],
  });

  factory AgentHistoryEntry.fromJson(Map<String, Object?> j) => AgentHistoryEntry(
    id: j['id']?.toString() ?? '',
    request: j['request']?.toString() ?? '',
    status: AgentRunStatus.parse(j['status']),
    summary: j['summary']?.toString() ?? '',
    createdAt: (DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now()).toLocal(),
    operations: [
      for (final o in (j['operations'] as List? ?? const []).whereType<Map>())
        AgentHistoryOperation.fromJson(Map<String, Object?>.from(o)),
    ],
    notes: [for (final n in (j['notes'] as List? ?? const [])) n.toString()],
  );

  final String id;
  final String request;
  final AgentRunStatus status;
  final String summary;
  final DateTime createdAt;
  final List<AgentHistoryOperation> operations;
  final List<String> notes;
}

@immutable
class AgentHistoryPage {
  const AgentHistoryPage(this.items, {this.nextBefore});
  final List<AgentHistoryEntry> items;

  /// Pass as `before` for the next page; null on the last page.
  final String? nextBefore;
}

abstract interface class AgentHistoryRepository {
  /// Newest first.
  Future<AgentHistoryPage> list({int limit = 20, String? before, AgentRunStatus? status});

  /// Deletes the user's agent history (records are not touched).
  Future<void> clear();
}

/// `GET /agent/history` and `DELETE /agent/history` on the FiNN API.
class RemoteAgentHistoryRepository implements AgentHistoryRepository {
  RemoteAgentHistoryRepository(this.api);
  final ApiClient api;

  @override
  Future<AgentHistoryPage> list({int limit = 20, String? before, AgentRunStatus? status}) async {
    final data = await api.get(
      '/agent/history',
      query: {'limit': '$limit', 'before': ?before, 'status': ?status?.name},
    );
    if (data is! Map) throw const AppFailure(FailureCode.unknown, 'Could not read your agent history.');
    return AgentHistoryPage(
      [
        for (final item in (data['items'] as List? ?? const []).whereType<Map>())
          AgentHistoryEntry.fromJson(Map<String, Object?>.from(item)),
      ],
      nextBefore: data['nextBefore']?.toString(),
    );
  }

  @override
  Future<void> clear() async {
    await api.send('DELETE', '/agent/history');
  }
}

/// History kept in memory (local mode and tests). Entries come from the
/// same confirmed outcomes the server would record.
class InMemoryAgentHistory implements AgentHistoryRepository {
  final List<AgentHistoryEntry> _entries = [];

  List<AgentHistoryEntry> get entries => List.unmodifiable(_entries);

  /// Adds or replaces (same id) an entry, keeping its first request text.
  void record(AgentHistoryEntry entry) {
    final i = _entries.indexWhere((e) => e.id == entry.id);
    if (i < 0) {
      _entries.insert(0, entry);
      return;
    }
    final old = _entries[i];
    final ops = {for (final o in old.operations) o.ref: o, for (final o in entry.operations) o.ref: o}.values.toList();
    _entries[i] = AgentHistoryEntry(
      id: old.id,
      request: old.request,
      status: runStatusOf(ops),
      summary: runSummaryOf(ops),
      createdAt: old.createdAt,
      operations: ops,
      notes: {...old.notes, ...entry.notes}.toList(),
    );
  }

  @override
  Future<AgentHistoryPage> list({int limit = 20, String? before, AgentRunStatus? status}) async {
    final all = [for (final e in _entries) if (status == null || e.status == status) e];
    final start = before == null ? 0 : (int.tryParse(before) ?? 0);
    final page = all.skip(start).take(limit).toList();
    return AgentHistoryPage(page, nextBefore: start + limit < all.length ? '${start + limit}' : null);
  }

  @override
  Future<void> clear() async => _entries.clear();
}

/// Same rules as the server (`server/agent/history.ts`): judged on the
/// operations the user approved.
AgentRunStatus runStatusOf(List<AgentHistoryOperation> ops) {
  final approved = ops.where((o) => o.status != 'declined').toList();
  final saved = approved.where((o) => o.saved).length;
  if (approved.isEmpty) return AgentRunStatus.declined;
  if (saved == approved.length) return AgentRunStatus.completed;
  return saved > 0 ? AgentRunStatus.partial : AgentRunStatus.failed;
}

String runSummaryOf(List<AgentHistoryOperation> ops) {
  int count(Set<String> s) => ops.where((o) => s.contains(o.status)).length;
  final saved = count({'saved', 'alreadySaved'});
  final parts = [
    if (ops.length == 1) (saved == 1 ? '1 change saved' : '') else '$saved of ${ops.length} saved',
    if (count({'failed', 'changed'}) > 0) '${count({'failed', 'changed'})} not saved',
    if (count({'skipped'}) > 0) '${count({'skipped'})} skipped',
    if (count({'declined'}) > 0) '${count({'declined'})} declined',
  ].where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? 'Nothing saved' : parts.join(', ');
}

/// Entries of [entries] inside [period] (`today`, `yesterday`, `week`,
/// `month`; anything else = all), relative to [now].
List<AgentHistoryEntry> entriesIn(List<AgentHistoryEntry> entries, String? period, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final (DateTime from, DateTime to) = switch (period) {
    'today' => (today, today.add(const Duration(days: 1))),
    'yesterday' => (today.subtract(const Duration(days: 1)), today),
    'week' => (today.subtract(Duration(days: today.weekday - 1)), today.add(const Duration(days: 1))),
    'month' => (DateTime(today.year, today.month), today.add(const Duration(days: 1))),
    _ => (DateTime(2000), today.add(const Duration(days: 1))),
  };
  return [for (final e in entries) if (!e.createdAt.isBefore(from) && e.createdAt.isBefore(to)) e];
}

/// A short, factual answer to "what did I ask you to do?", built from the
/// stored outcomes (no model call).
String historyAnswer(List<AgentHistoryEntry> entries, {String? period, required DateTime now, int max = 5}) {
  final list = entriesIn(entries, period, now);
  final when = switch (period) {
    'today' => ' today',
    'yesterday' => ' yesterday',
    'week' => ' this week',
    'month' => ' this month',
    _ => '',
  };
  if (list.isEmpty) return 'You haven\'t asked me to change anything$when.';
  String time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String day(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return 'today ${time(t)}';
    if (d == today.subtract(const Duration(days: 1))) return 'yesterday ${time(t)}';
    return '${t.day}/${t.month} ${time(t)}';
  }

  String clip(String s) => s.length <= 60 ? s : '${s.substring(0, 59)}…';
  final lines = [
    for (final e in list.take(max)) '• ${day(e.createdAt)}: "${clip(e.request)}" — ${e.summary.toLowerCase()}.',
  ];
  final more = list.length > max ? '\n${list.length - max} more in History.' : '';
  return 'Here is what you asked me$when:\n${lines.join('\n')}$more';
}
