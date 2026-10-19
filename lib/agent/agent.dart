/// FiNN agent module: natural-language record keeping with LLM tool calling.
///
/// The rest of the app uses only what is exported here:
/// * [AgentModePanel] / [agentModeProvider]: agent mode, opened from the
///   [AgentOrb] in the navigation bar (the app shell locks everything else);
/// * [AgentScreen]: the same experience full screen (route `AppRoutes.assistant`);
/// * [voiceInputProvider] / [speechRecognizerProvider]: voice requests
///   (on-device speech-to-text);
/// * [agentControllerProvider]: chat state and commands (for other entry
///   points such as voice later);
/// * [llmProviderProvider] / [agentConfigProvider]: override to swap the
///   model provider or limits (tests use a scripted provider).
///
/// See `docs/AGENT.md` for the architecture, tools and how to extend it.
library;

export 'agent_config.dart' show AgentConfig;
export 'application/agent_controller.dart'
    show AgentController, AgentViewState, AgentStatus, ChatEntry, UserChatEntry, AgentChatEntry, ActionDeck, DeckSlot, DeckAttempt, CardDecision;
export 'application/agent_providers.dart';
export 'llm/llm_provider.dart' show LlmProvider, CancellationToken;
export 'application/agent_mode.dart' show agentModeProvider, AgentModeController;
export 'presentation/agent_screen.dart' show AgentScreen, AgentModePanel, AgentExperience;
export 'presentation/widgets/agent_visualizer.dart' show AgentVisualizer, AgentPresence;
export 'presentation/widgets/agent_logo.dart' show AgentOrb, FinnAgentMark;
export 'voice/speech_recognizer.dart';
export 'voice/voice_input_controller.dart';
