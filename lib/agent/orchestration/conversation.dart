import '../llm/llm_types.dart';

/// Conversational context only: what the user said, what the model replied
/// and the tool exchanges in between. Financial data is never stored here
/// beyond the tool results the model already saw; fresh data always comes
/// from the tools.
class Conversation {
  Conversation({required this.id});

  final String id;
  final List<LlmMessage> _messages = [];

  List<LlmMessage> get messages => List.unmodifiable(_messages);

  bool get isEmpty => _messages.isEmpty;

  void add(LlmMessage m) => _messages.add(m);

  void addAll(Iterable<LlmMessage> ms) => _messages.addAll(ms);

  /// Index of the next message; used to roll back a failed turn.
  int get mark => _messages.length;

  /// Drops everything after [mark].
  void rollbackTo(int mark) {
    if (mark < _messages.length) _messages.removeRange(mark, _messages.length);
  }

  /// The messages to send: the most recent [maxTurns] user turns, trimmed
  /// further (oldest turns first) until under [maxChars] and roughly
  /// [maxItems] provider input items (the relay accepts at most 200). Turns
  /// are cut only at user messages so a tool call is never separated from
  /// its result.
  List<LlmMessage> window({required int maxTurns, required int maxChars, int maxItems = 180}) {
    final starts = <int>[
      for (var i = 0; i < _messages.length; i++)
        if (_messages[i].role == LlmRole.user) i,
    ];
    if (starts.isEmpty) return List.unmodifiable(_messages);
    var first = starts.length > maxTurns ? starts[starts.length - maxTurns] : starts.first;
    int size(int from) {
      var n = 0;
      for (var i = from; i < _messages.length; i++) {
        final m = _messages[i];
        n += (m.content?.length ?? 0) + m.toolCalls.fold(0, (a, c) => a + c.arguments.length + c.name.length);
      }
      return n;
    }

    // An assistant turn expands to its text, reasoning and each tool call.
    int items(int from) =>
        _messages.skip(from).fold(0, (n, m) => n + (m.role == LlmRole.assistant ? 2 + m.toolCalls.length : 1));

    var startIndex = starts.indexOf(first);
    while (startIndex < starts.length - 1 && (size(first) > maxChars || items(first) > maxItems)) {
      startIndex++;
      first = starts[startIndex];
    }
    return List.unmodifiable(_messages.sublist(first));
  }
}
