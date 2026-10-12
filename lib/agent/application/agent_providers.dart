import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/action_providers.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/api_config.dart';
import '../../data/remote/remote_providers.dart';
import '../agent_config.dart';
import '../llm/groq/groq_chat_provider.dart';
import '../llm/llm_provider.dart';
import '../llm/llm_transport.dart';
import '../tools/tool_catalog.dart';
import 'agent_controller.dart';

final agentConfigProvider = Provider<AgentConfig>((ref) => const AgentConfig());

/// The language model behind the agent, or null when none is available.
///
/// Groq is reached through the FiNN API relay, which holds the API key, so
/// the agent needs remote mode (`--dart-define=FINN_API_URL`). Replace this
/// provider to use another [LlmProvider]; nothing else changes.
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
  return GroqChatProvider(FinnRelayTransport(api));
});

final agentToolboxProvider = Provider<AgentToolbox>((ref) => AgentToolbox.standard(ref.watch(actionRegistryProvider)));

/// Chat state and commands for the assistant screen.
final agentControllerProvider = NotifierProvider<AgentController, AgentViewState>(AgentController.new);
