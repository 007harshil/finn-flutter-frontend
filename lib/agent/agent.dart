/// FiNN agent module: natural-language record keeping with LLM tool calling.
///
/// The rest of the app uses only what is exported here:
/// * [AgentModePanel] / [agentModeProvider]: agent mode, opened from the
///   [AgentOrb] in the navigation bar (the app shell locks everything else);
/// * [AgentScreen]: the same console full screen (route `AppRoutes.assistant`);
/// * [voiceInputProvider] / [speechTranscriberProvider]: voice requests;
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
export 'application/agent_mode.dart' show agentModeProvider, AgentModeController;
export 'presentation/agent_screen.dart' show AgentScreen, AgentModePanel, AgentConsole;
export 'presentation/widgets/agent_logo.dart' show AgentOrb, FinnAgentMark;
export 'voice/speech_transcriber.dart' show SpeechTranscriber, FinnRelayTranscriber;
export 'voice/voice_capture.dart' show VoiceCapture, VoiceClip, RecordVoiceCapture;
export 'voice/voice_input_controller.dart';
