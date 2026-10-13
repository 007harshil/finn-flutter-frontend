import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/action_providers.dart';
import '../../app/di/core_providers.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/api_config.dart';
import '../../data/remote/remote_providers.dart';
import '../../data/remote/sync_engine.dart';
import '../agent_config.dart';
import '../execution/plan_gateway.dart';
import '../history/agent_history.dart';
import '../llm/chat_completions_provider.dart';
import '../llm/llm_provider.dart';
import '../llm/llm_transport.dart';
import 'agent_controller.dart';

final agentConfigProvider = Provider<AgentConfig>((ref) => const AgentConfig());

/// The language model behind the agent, or null when none is available.
///
/// The model (OpenAI) is reached through the FiNN API relay, which holds the
/// API key, so the agent needs remote mode (`--dart-define=FINN_API_URL`).
/// Replace this provider to use another [LlmProvider]; plan resolution,
/// execution, history and the UI do not change.
final llmProviderProvider = Provider<LlmProvider?>((ref) {
  final backend = ref.watch(remoteBackendProvider);
  if (backend == null) return null;
  final c = backend.config;
  final api = ApiClient(
    config: ApiConfig(
      apiUrl: c.apiUrl,
      // Model calls take longer than record calls; the relay times out first.
      timeout: ref.watch(agentConfigProvider).requestTimeout,
    ),
    auth: backend.auth,
  );
  return ChatCompletionsProvider(FinnRelayTransport(api));
});

/// Agent history: the FiNN API in remote mode, in memory otherwise.
final agentHistoryProvider = Provider<AgentHistoryRepository>((ref) {
  final backend = ref.watch(remoteBackendProvider);
  return backend == null ? InMemoryAgentHistory() : RemoteAgentHistoryRepository(backend.api);
});

/// Where the agent previews and executes plans: `POST /plans/*` in remote
/// mode (one request per wave), the local dispatcher otherwise.
final agentPlanGatewayProvider = Provider<PlanGateway>((ref) {
  final backend = ref.watch(remoteBackendProvider);
  if (backend != null) return RemotePlanGateway(backend.api, engine: backend.engine);
  final history = ref.watch(agentHistoryProvider);
  return DispatcherPlanGateway(
    ref.watch(actionDispatcherProvider),
    history: history is InMemoryAgentHistory ? history : null,
    now: () => ref.read(clockProvider).now(),
  );
});

/// UTC offsets (minutes) of fixed-offset zones, for "today" in the user's
/// configured time zone. Zones with daylight saving fall back to the
/// device's own date.
const _fixedZones = <String, int>{
  'Asia/Kolkata': 330,
  'Asia/Calcutta': 330,
  'Asia/Colombo': 330,
  'Asia/Kathmandu': 345,
  'Asia/Dhaka': 360,
  'Asia/Dubai': 240,
  'Asia/Karachi': 300,
  'Asia/Singapore': 480,
  'Asia/Kuala_Lumpur': 480,
  'Asia/Tokyo': 540,
  'UTC': 0,
  'Etc/UTC': 0,
};

/// Today's date in the time zone the server uses for this user (synced
/// preferences), so "yesterday" means the same day to the app and the API.
final agentTodayProvider = Provider<DateTime Function()>((ref) {
  final clock = ref.watch(clockProvider);
  final engine = ref.watch(remoteBackendProvider)?.engine;
  return () {
    final now = clock.now();
    final zone = engine?.value(SyncValues.preferences)?['timeZone'];
    final offset = zone is String ? _fixedZones[zone] : null;
    final local = offset == null ? now : now.toUtc().add(Duration(minutes: offset));
    return DateTime(local.year, local.month, local.day);
  };
});

/// Chat state and commands for the assistant screen.
final agentControllerProvider = NotifierProvider<AgentController, AgentViewState>(AgentController.new);
