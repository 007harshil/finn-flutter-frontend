/// FiNN agent module: natural-language record keeping with LLM tool calling.
///
/// The rest of the app uses only what is exported here:
/// * [AgentScreen]: the chat UI (route `AppRoutes.assistant`);
/// * [agentControllerProvider]: chat state and commands (for other entry
///   points such as voice later);
/// * [llmProviderProvider] / [agentConfigProvider]: override to swap the
///   model provider or limits (tests use a scripted provider).
///
/// See `docs/AGENT.md` for the architecture, tools and how to extend it.
library;

export 'agent_config.dart' show AgentConfig;
export 'application/agent_controller.dart' show AgentController, AgentViewState, AgentStatus, ChatEntry, UserChatEntry, AgentChatEntry;
export 'application/agent_providers.dart';
export 'llm/llm_provider.dart' show LlmProvider, CancellationToken;
export 'presentation/agent_screen.dart' show AgentScreen;
