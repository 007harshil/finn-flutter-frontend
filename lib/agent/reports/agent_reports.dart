import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/remote/api_client.dart';
import '../../data/remote/remote_providers.dart';

/// Why a user flags an assistant reply (Google Play requires apps that
/// generate content with AI to let users report it without leaving the app).
enum AgentReportReason {
  offensive('Offensive or hateful'),
  harmful('Harmful or unsafe advice'),
  inaccurate('Wrong or misleading'),
  other('Something else');

  const AgentReportReason(this.label);
  final String label;
}

/// Sends reports of assistant replies to the developer.
abstract interface class AgentReports {
  Future<void> report({
    required AgentReportReason reason,
    required String reply,
    String? request,
    String? note,
  });
}

/// `POST /agent/reports` on the FiNN API.
class RemoteAgentReports implements AgentReports {
  RemoteAgentReports(this.api);
  final ApiClient api;

  @override
  Future<void> report({required AgentReportReason reason, required String reply, String? request, String? note}) async {
    await api.post(
      '/agent/reports',
      body: {
        'reason': reason.name,
        'reply': reply,
        'request': ?request,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }
}

/// Local mode and tests: keeps reports in memory.
class InMemoryAgentReports implements AgentReports {
  final List<({AgentReportReason reason, String reply, String? request, String? note})> sent = [];

  @override
  Future<void> report({required AgentReportReason reason, required String reply, String? request, String? note}) async {
    sent.add((reason: reason, reply: reply, request: request, note: note));
  }
}

final agentReportsProvider = Provider<AgentReports>((ref) {
  final backend = ref.watch(remoteBackendProvider);
  return backend == null ? InMemoryAgentReports() : RemoteAgentReports(backend.api);
});
