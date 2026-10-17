/// Client-side guardrails: keep the agent a FiNN money assistant.
///
/// The backend relay is the authority (`finn-backend/server/agent/guardrails.ts`
/// pins a scope policy, screens input, runs moderation and filters output);
/// these checks mirror its input and output rails so an out-of-scope request
/// is refused without a model call, and a reply carrying code or secrets is
/// never shown even when talking to an older server.
///
/// Matching is deliberately specific (high precision): ordinary money
/// messages ("paid 500 for a python course", "promo code SAVE10", "Shell
/// petrol 2000") must still reach the model.
abstract final class AgentGuard {
  /// Shown when a request or reply is outside FiNN's scope.
  static const refusal =
      "I can only help with your FiNN money records, like logging expenses, income, debts, budgets and goals. I can't help with that.";

  static const _languages =
      r'python|javascript|typescript|java|kotlin|swift|golang|rust|ruby|php|perl|dart|flutter|react|node\.?js|next\.?js|c\+\+|c#|html|css|sql|bash|powershell|shell|assembly|matlab|scala|haskell|lua|vba|excel formula|regex';

  /// Languages that never name a shop, place or person.
  static const _strictLanguages = r'python|javascript|typescript|golang|kotlin|php|c\+\+|c#|sql|bash|powershell|html|css';
  static const _codeNouns = r'code|script|snippet|function|algorithm|syntax|regex';

  /// "code" that is not a coupon, OTP or bank code.
  static const _codeWord =
      r'(?<!(promo|coupon|discount|referral|voucher|gift|otp|pin|ifsc|swift|postal|zip|area|qr|bar|dress)\s)code';

  static final _input = [
    RegExp('\\b($_languages)\\b\\W+(\\w+\\W+){0,3}($_codeNouns)\\b', caseSensitive: false),
    RegExp('\\b($_codeNouns)\\b\\W+(\\w+\\W+){0,3}(in|using|with)\\s+($_languages)\\b', caseSensitive: false),
    RegExp('\\b(in|using|with)\\s+($_strictLanguages)\\s*[?.!]*\\s*\$', caseSensitive: false),
    RegExp(
      '\\b(write|generate|create|give|show|make|build|implement|debug|fix|explain|convert|refactor|optimi[sz]e)\\b\\W+(\\w+\\W+){0,4}($_codeWord|script|snippet|function|algorithm|regex|sql|program (to|for|that)|html page|web ?page|website)\\b',
      caseSensitive: false,
    ),
    RegExp(r'```|<script\b|\bdef \w+\(|\bfunction \w*\(|#include\b|\bconsole\.log\(', caseSensitive: false),
    RegExp(
      r'\b(system prompt|developer prompt|initial prompt|hidden prompt|your (instructions|prompt)|source ?code|code ?base|backend|back-end|frontend|front-end|tech ?stack|database (schema|structure|tables?|password)|db schema|server (code|config|details)|env(ironment)? (variables?|file)|\.env\b|api[ _-]?keys?|secret keys?|private keys?|access tokens?|jwt|credentials|(which|what) (llm|ai model|gpt|language model)\b)',
      caseSensitive: false,
    ),
    RegExp(r'\bhow (is|was|are|were) (finn|this app|the app|you) (built|made|coded|developed|programmed|implemented)\b', caseSensitive: false),
    RegExp(
      r'\b(ignore|disregard|forget|override|bypass)\b\W+(\w+\W+){0,3}(previous|prior|above|earlier|all|your|the|system|safety)\W+(\w+\W+){0,2}(instructions?|rules?|prompts?|polic(y|ies)|guidelines|restrictions|guardrails)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(you are now|from now on you are|pretend (to be|you are)|act as (an? )?(unrestricted|unfiltered|different|new|evil)|developer mode|god mode|jailbreak|do anything now|without (any )?(rules|restrictions|filters)|(repeat|print|reveal|output) (the text|the words|your instructions|the instructions|everything above|the above))',
      caseSensitive: false,
    ),
  ];

  static final _code = [
    RegExp('```'),
    RegExp(r'^\s*def \w+\(.*\):', multiLine: true),
    RegExp(r'^\s*(from [\w.]+ import [\w*, ]+|import [\w.]+ as \w+|import \w+\.[\w.]+);?\s*$', multiLine: true),
    RegExp(r'^\s*#include\s*<', multiLine: true),
    RegExp(r'\bfunction\s*\w*\s*\([^)]*\)\s*\{|=>\s*\{|\b(console\.log|System\.out\.print|printf|print)\(|\bpublic static void|<\?php|<script\b|<\/\w+>'),
    RegExp(r'^\s*(const|let|var)\s+\w+\s*=\s*.+;\s*$', multiLine: true),
    RegExp(r'\b(SELECT\s+[\w*, ]+\s+FROM|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DROP\s+TABLE|CREATE\s+TABLE)\b'),
    RegExp(r'^\s*(\$|>)?\s*(sudo|npm|pip|curl|wget|git|rm -rf|chmod)\s+\S+', multiLine: true),
  ];

  static final _secret = [
    RegExp(r'\bsk-[A-Za-z0-9_-]{16,}'),
    RegExp(r'\bgsk_[A-Za-z0-9]{20,}'),
    RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
    RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
    RegExp(r'\beyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,}'),
    RegExp(r'\b(postgres(ql)?|mysql|mongodb(\+srv)?|redis):\/\/\S+', caseSensitive: false),
    RegExp(r'\b(OPENAI_API_KEY|GROQ_API_KEY|AUTH_JWT_SECRET|SMTP_PASS|DATABASE_URL|SUPABASE_[A-Z_]+)\b'),
    RegExp(r'\b(api[_-]?key|secret|password|passwd|token)\s*[:=]\s*\S{8,}', caseSensitive: false),
  ];

  /// True when the user's message asks for something outside FiNN's scope
  /// (code, app internals, secrets) or tries to override the agent's rules.
  static bool isOutOfScope(String text) => _input.any((r) => r.hasMatch(text));

  /// True when model-written [text] carries code or a secret.
  static bool isUnsafeOutput(String text) => _secret.any((r) => r.hasMatch(text)) || _code.any((r) => r.hasMatch(text));
}
