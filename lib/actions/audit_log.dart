import 'dart:async';

import 'package:flutter/foundation.dart';

import 'action.dart';

@immutable
class AuditEntry {
  const AuditEntry({
    required this.actionId,
    required this.summary,
    required this.channel,
    required this.at,
    required this.succeeded,
    this.confirmedBy,
    this.failure,
  });

  final String actionId;
  final String summary;
  final ActionChannel channel;
  final DateTime at;
  final bool succeeded;
  final String? confirmedBy;
  final String? failure;
}

/// In-memory record of executed operations (newest first), shown in
/// Settings → Activity log. A backend would persist this server-side.
class AuditLog {
  AuditLog({this.capacity = 200});

  final int capacity;
  final List<AuditEntry> _entries = [];
  final _controller = StreamController<List<AuditEntry>>.broadcast();

  List<AuditEntry> get entries => List.unmodifiable(_entries);

  Stream<List<AuditEntry>> watch() async* {
    yield entries;
    yield* _controller.stream;
  }

  void record(AuditEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > capacity) _entries.removeLast();
    _controller.add(entries);
  }
}
