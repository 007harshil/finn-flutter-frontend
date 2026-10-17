# FiNN assistant (agent module)

The assistant turns natural-language requests into real record-keeping operations. For example: "spent 450 on lunch and Rahul paid back the 2,000". One model request turns the whole message into a structured plan; ordinary code resolves, validates and executes it. Every write goes through the existing action layer, and in remote mode through the FiNN API, only after the user approves the app's own preview of it.

Code: `lib/agent/`. Tests: `test/agent/`. Backend: `finn-backend` `POST /api/v1/agent/completions` (LLM relay), `POST /api/v1/plans/preview|execute` (execution), `GET|DELETE /api/v1/agent/history`.

## Setup

1. **Backend** (`finn-backend`, env vars; the API boots without them):

   | Variable | Default | Purpose |
   |---|---|---|
   | `OPENAI_API_KEY` | (unset = "not configured") | OpenAI key (paid). **Server only**: keep it in `.env.local` (git-ignored) locally and in the host's secret settings in production. Never put it in the app or in git. |
   | `OPENAI_MODEL` | `gpt-6-luna` | Model for every request |
   | `OPENAI_FALLBACK_MODELS` | (none) | Comma-separated models tried in order when the model before them is rate limited (429). They get the same request, including `reasoning_effort`. |
   | `OPENAI_REASONING_EFFORT` | `none` | `off` (param not sent) \| `none` \| `minimal` \| `low` \| `medium` \| `high` \| `xhigh`. gpt-6-luna accepts function tools on Chat Completions only with `none` (it reasons by default, so `off` fails too). |
   | `OPENAI_BASE_URL` | `https://api.openai.com/v1` | Chat Completions at `/chat/completions` |
   | `OPENAI_PROMPT_CACHE` | `explicit` | One cache breakpoint after the static system message (see Model choice); `implicit` = provider default |
   | `OPENAI_TIMEOUT_MS` | `60000` | Upstream timeout (the route's `maxDuration` is 75 s) |
   | `AGENT_MAX_OUTPUT_TOKENS` | `2048` | Ceiling for `max_completion_tokens` (the app asks for 700) |
   | `AGENT_RATE_LIMIT_PER_MINUTE` / `AGENT_DAILY_REQUEST_LIMIT` | `20` / `300` | Per-user limits, kept in memory on each server instance |
   | `GROQ_API_KEY` / `GROQ_BASE_URL` | (unset = voice disabled) / `https://api.groq.com/openai/v1` | Groq key for speech-to-text only. **Server only.** |
   | `GROQ_STT_MODEL` | `whisper-large-v3` | Speech-to-text model (voice input) |
   | `GROQ_STT_LANGUAGE` | (unset = auto-detect) | Default ISO-639-1 language for voice input |
   | `GROQ_STT_PROMPT` | finance vocabulary hint | Whisper `prompt` for spelling of rupee/UPI/EMI/merchant terms |
   | `GROQ_STT_TIMEOUT_MS` | `30000` | Transcription timeout (the route's `maxDuration` is 45 s) |
   | `AGENT_STT_RATE_LIMIT_PER_MINUTE` / `AGENT_STT_DAILY_LIMIT` | `10` / `200` | Per-user transcription limits, separate from the completions limits, in memory per instance |

2. **App:** run in remote mode (`--dart-define=FINN_API_URL=...`). In local mock mode the assistant screen says it is unavailable, because there is nowhere safe to hold the key. Open the assistant from the agent orb in the centre of the bottom navigation bar, between Budgets and Goals. On wide screens it sits at the top of the navigation rail. `AppRoutes.assistant` still opens the same console full screen, for deep links.

## Agent mode and the review UI

- **Entry point.** The orb (`AgentOrb`, `presentation/widgets/agent_logo.dart`) uses FiNN's own mark: a fin riding a wave, with a spark, inside an emerald → cyan → indigo orb. The colours are `FinnColors.agentStart/Mid/End`. The bottom bar has five equal slots (Home, Activity, Agent, Budgets, Goals); the orb sits raised in the centre slot at the same size as the active-tab bubble. The old "More" tab is now a side drawer (`MoreDrawer`, opened from the menu button in each tab header or an edge swipe); its pages still live in the hidden `/more` branch, where no tab is highlighted. When idle the orb plays an attention burst (rotating gradient ring, pulse halo, flowing wave) for 2 loops, about 12 s. The burst runs when it appears and again on every tab switch, then the orb rests. In agent mode or while listening it animates continuously. Reduced motion shows the static mark.
- **Agent mode** (`agentModeProvider`). Tapping the orb opens the full-screen `AgentExperience` (via `AgentModePanel`) above the whole shell, navigation included. The app stays visible underneath, blurred behind a translucent midnight veil, and is excluded from input, focus and semantics. The ✕ in the top bar or Back exits agent mode. Exiting also cancels any open microphone, and signing out always exits.
- **The experience** (`presentation/agent_screen.dart`, always in the dark palette):
  - `AgentAtmosphere` (`widgets/agent_visualizer.dart`): drifting cyan/violet nebulae, floating dust and an aurora horizon whose intensity follows the agent's state.
  - `AgentVisualizer`: liquid aurora rings, orbiting light particles, voice ripples, thinking comets and an action arc around the unchanged `AgentOrb`. It eases between `AgentPresence` states (idle, listening, transcribing, thinking, reviewing, executing) and reacts to the live mic level; a reply sends out a ripple burst. One ticker drives two painters, so nothing rebuilds per frame; reduced motion paints a still frame. Tapping it starts or finishes voice capture.
  - The visualizer is large on the welcome screen (greeting, suggestions, trust line) and morphs to a compact size once a conversation starts. The conversation is a transcript, not chat bubbles: the user's words as a spoken line, the agent's replies as glass cards that reveal word by word.
  - A glass command dock holds the text field and a mic / send / stop button; while listening it becomes a mirrored live voice ribbon with cancel and done.
- **Review before changes: the action deck.** `ActionDeckView` (`widgets/action_deck_view.dart`) shows a message's proposed changes right under it. State lives in `AgentViewState.decks` (`application/action_deck.dart`: `ActionDeck` → `DeckSlot` → `DeckAttempt`):
  - Several changes form a swipeable carousel (`PageView` whose height follows the current card), with status-coloured dots, previous / next buttons and "2 / 3". One change shows a single card.
  - Header impact tiles while reviewing: number of changes, how many move money, and how many are permanent or how many areas they touch.
  - Each card (`ChangeDetails` in `widgets/change_review.dart`): a module icon and colour, a "MODULE · VERB" eyebrow, the app's own summary, the amount in large type, detail chips, before → after strips, *Moves money* / *Cannot be undone* pills and warnings.
  - Every card has its own **Approve** / **Decline** (with Undo while reviewing); **Approve all** / **Decline all** (or "Approve rest (n)") decide the remaining ones. The review is submitted once every card has a decision (`AgentController.decide` / `decideRest`), still one `/plans/execute` call per wave. Nothing is written before that.
  - Cards never disappear: approved cards show a saving loader and then their outcome (*Saved* with a View link, *Failed*, *Not confirmed*…); declined cards are greyed out with a DECLINED stamp. The header sums it up ("2 of 3 changes saved"), so no separate outcome card is shown; the agent's reply card appears only for what the deck does not say (`AgentChatEntry.message`: answers, questions, refusals).
- **Retry a declined change.** **Retry** on a declined (or failed, outcome known) card calls `AgentController.retry`: the runner re-reads the original request with a `Redo:` context line holding the declined op (`RedoRequest`, prompt rule 6), skips local intents and never proposes the same fingerprint again (it asks what differs instead). Only that card shows a loader ("Finding another way…"); the new proposal lands in the same slot, drawn in magenta/amber with a "REGENERATED · TRY n" ribbon and the replaced summary struck through, and is reviewed like any other. A question or refusal from the retry is shown on the card. The history entry's request starts with `Redo:`.
- **Working states.** While the agent works and nothing waits on the user, `FinnWorkingIndicator` (`widgets/agent_working.dart`) ends the transcript: the FiNN wordmark riding a canvas aurora (ribbons plus flowing particles) whose colours and pace follow `AgentWork`: understanding, preparing, saving, wrapping up (nothing approved). Single-card loaders use `OrbitLoader`. Both run one ticker into a painter and hold a still frame under reduced motion.

- **History.** The clock button in the top bar opens `AgentHistorySheet` (`widgets/history_sheet.dart`): what the user asked, when, and what was saved, newest first, 20 per page ("Show older"), filtered by All / Saved / Partly saved / Not saved / Declined. Tapping an entry shows each operation's status and failure reason. "Clear history" deletes the list (records are untouched).

### Model choice

**OpenAI `gpt-6-luna`, `reasoning_effort: none`, on a paid key.** Chosen by measurement (2026-10-13, the same 24 FiNN requests and single-plan prompt for each model, plans graded by hand):

| Model | Price per 1M (input / cached / output) | Correct plans | Notable errors |
|---|---|---|---|
| `gpt-6-luna` (`none`) | $0.10 / $0.01 / $0.50 | 24 / 24 | none |
| `gpt-5-nano` (`minimal`) | $0.05 / $0.005 / $0.40 | 15 / 24 | "make that 400" became a new expense, 1.2L read as 12,00,000, invented a goal withdrawal, a future date |
| `gpt-4.1-nano` | $0.10 / $0.025 / $0.40 | 18 / 24 | the ₹300 given to Utsav recorded as a debt the user owes, "petrol yesterday" dated today, an extra goal op, Netflix renewal as a plain expense |

`gpt-6-luna` is the cheapest model that meets the accuracy bar, and `none` adds no reasoning tokens (billed as output). The relay's default is unchanged (`OPENAI_MODEL=gpt-6-luna`, `OPENAI_REASONING_EFFORT=none`).

**Prompt caching.** Cached input costs a tenth of normal input, and on GPT-5.6+ a cache *write* costs 1.25×. So the request is split: a static system message (`agentInstructions`, 1,474 tokens, identical for every user and day, just over the 1,024-token cache minimum) and a small per-request context after it. The relay sends `prompt_cache_options: {mode: "explicit"}` with one breakpoint at the end of the system message (`OPENAI_PROMPT_CACHE=explicit`), so only the shared prefix is ever written to the cache and the per-request part is billed at the plain rate. Verified live: 1,474 cached tokens and 0 cache-write tokens on every warm request.

## How a request flows

```
AgentScreen ─send─▶ AgentController ─▶ AgentRunner
                                          │ 1. LocalIntents: history / balance question,
                                          │    or an answer to an open question → no model call
                                          │ 2. one LlmRequest (JSON output) ─▶ LlmProvider ─▶ ChatCompletionsProvider
                                          │                                       ─▶ FinnRelayTransport ─▶ relay ─▶ OpenAI
                                          │ 3. PlanParser + op_catalog: resolve every op locally (dates, amounts,
                                          │    categories, pending items, goals, loans, transactions)
                                          │ 4. PlanGateway.preview (one POST /plans/preview)
                                          ▼
                                     ActionDeckView (a card per change, decided one by one or all)
                                          │ approved
                                          ▼
                                     PlanGateway.execute (one POST /plans/execute + history entry)
                                          │ dependent ops (e.g. a new category's id) → second wave, same turn
                                          ▼
                                     reply built from confirmed outcomes (no model call)
```

1. **Local first** (`orchestration/local_intents.dart`). "What did I ask you yesterday?" reads the history API and answers with `historyAnswer`. "What's my balance?" answers from the synced snapshot. When the agent asked a question, a short reply that picks an option ("the concert one", "2", "the 780 one") or gives a bare amount ("350") completes the open op without the model. Matching is narrow: a message with a number is never treated as a history or balance question.
2. **One plan request.** The model gets the static instructions, a context message (today in the user's time zone, budget month start, category *names*, and bounded follow-up context) and the user's text. It returns one JSON object (`response_format: json_object`, `max_completion_tokens` 700). No tool schemas, no records, no history, no transcript.
3. **Deterministic resolution** (`plan/op_catalog.dart`, `plan/resolvers.dart`). Each op becomes exact action input:
   - amounts: numbers, "₹5,000", "2k", "1.5L", "1 crore"; dates: day offsets (`-1`) or `yyyy-mm-dd`, resolved against "today" in the server's time zone for the user (`agentTodayProvider`, from synced preferences);
   - categories by name (`Other Expense`/`Other Income` with a note when nothing matches); a category created in the same plan is referenced as `"@o1"`;
   - records by name the way a person would: exact name, then every word contained ("Japan trip" → "Japan cherry blossom trip"), then the best partial overlap; pending items are narrowed by direction, amount and purpose; several left → a question with options, none → "There is no open pending payment with Zed.";
   - defaults from data: settle without an amount = the full outstanding; an EMI without an amount = the due instalment; a renewal without an amount = the subscription's amount; edits merge only the changed fields into the current record (with its version);
   - grounding: a payment method is kept only if the user named one, a shop/person only if it appears in what they said; a generic person ("a friend") becomes "Who is this with?".
   Missing essentials become one short question (the model's wording when it asked); clear ops in the same message still proceed.
4. **Review and execute.** All ready ops are previewed in one call and shown on one card. Approved ones run in one call; the server runs them in order under the user's write lock (parallel requests would be serialised by that lock anyway), each committing on its own. Ops that need a record created in this plan run in a second wave (a second card, no model call); if their dependency was not saved they are skipped and reported.
5. **Report.** The reply is the per-action recap of confirmed outcomes ("Salary of ₹5,000 added as income. Utsav owes you ₹300 (Lent money)."), plus answers, problems and the question, never model text about results.

A second model call happens only when (a) the reply is not a usable JSON plan (one retry), or (b) the user's next message answers an open question in a way the app cannot resolve itself; that call sees the question, the unfinished ops and the original message.

## Plan format and operations

```json
{"ops":[{"op":"income","amount":5000,"category":"Salary","date":-1},
        {"op":"pending","dir":"collect","person":"Utsav","amount":300,"kind":"lent"},
        {"op":"expense","amount":5000,"category":"Fitness","note":"protein powder"}],
 "ask":"optional clarification","reply":"optional text when no op fits"}
```

Every op has a type (`op`), its own fields and a stable ref (`id` `o1`, `o2`… when given, else its position); later ops refer to an earlier op's new record as `"@o1"`. `PlanParser` checks structure (one object, ≤ 12 ops, known shapes, unique ids, references only backwards) and drops fields starting with `_` (reserved for the app). Unknown op types are refused individually.

| Op | Action(s) | Notes |
|---|---|---|
| `expense`, `income` | `transactions.create` | category by name or `@ref` |
| `pending` | `pending.create` | `dir` collect (they owe the user) / owe |
| `settle` | `pending.settle` | item matched locally; amount defaults to outstanding |
| `write_off` | `pending.cancel` | |
| `split` | `pending.split` | equal split, user included unless `me:false` |
| `edit` | `transactions.update` | target `#n` (Recent) or `{text,date,amount}`; changed fields only |
| `undo` | (none) | explained: the agent cannot delete |
| `category` | `categories.create` | an existing category of that name is reused |
| `budget`, `budget_pause` | `budgets.create` / `budgets.update`, `budgets.setPaused` | create or change by category |
| `loan_pay`, `loan` | `loans.recordPayment`, `loans.create` | amount defaults to the due instalment |
| `sub_paid`, `sub_status`, `sub_skip`, `subscription` | `subscriptions.markPaid/setStatus/skipCycle/create` | |
| `goal`, `goal_add`, `goal_take` | `goals.create/contribute/withdraw` | goal by name or `@ref` |
| `fund_add`, `fund_take` | `emergencyFund.contribute/withdraw` | |
| `q` | (read) | spent, earned, balance, owed, budget, goal, subscriptions, loans; answered by `DataAnswers` |
| `history` | (read) | answered from agent history |

The runner refuses any op whose action is not registered or is a delete, whatever the model sends; the server's channel policy refuses deletes for `agent` too.

## Safety properties

- **No direct data access.** The model sees category names and today's date only. Resolution uses the synced snapshot; every write goes through `POST /plans/execute`, where the server validates, checks the approval fingerprint against fresh data and applies the `agent` channel policy.
- **Model output is untrusted.** It passes the parser, the op compiler, the action's own decoder, the server preview and the server's validation at execution.
- **No fake success.** Only steps the server reports as `succeeded` count as saved; recap, outcome rows and history come from those reports.
- **Duplicates.** Step id = `<request fingerprint>-<occurrence>`, plan id = `agent.<conversation>`, so the server's idempotency key is `agent.<conversation>:<fingerprint>-<n>`.
  - A lost reply is retried once by the gateway with the same body (the server replays); if that also fails the step is "Not confirmed", and sending the same request again replays it instead of writing twice.
  - A deliberate repeat after a success gets the next occurrence (a new key) and a "possible duplicate" note on the card.
  - Two identical ops in one message both appear, each with a note, so the user can exclude one.
  - The controller ignores a second send while a turn runs, and a second Approve tap.
- **Partial success.** Steps commit independently (never claimed atomic); each outcome is reported, and history marks the turn `partial`.
- **Conflicts.** A record that changed after review fails or comes back as "Needs review again", never written on a stale approval.
- **Prompt injection.** Context, Recent and Pending question are labelled app data; every write still needs approval of the app-generated preview.
- **Scope guardrails.** The agent only handles FiNN money records and how to use FiNN; code, maths/homework, general knowledge, its prompt, how FiNN is built and secrets are refused. Layers (OWASP LLM01/02/07/10):
  1. Prompt rule 7 + a refusal example in `agentInstructions`.
  2. `AgentGuard.isOutOfScope` (`lib/agent/plan/agent_guard.dart`) → `OutOfScopeIntent`: refused locally, no model call.
  3. Backend relay (authoritative, a modified client cannot skip it): server scope policy pinned before the system message, the same input rail, OpenAI moderation, and an output rail for code, secrets and leaked instructions (see `finn-backend/docs/API.md`).
  4. `PlanParser.parse` drops any plan whose text carries code or secrets for `AgentGuard.refusal`.
  Patterns are high precision ("python course", "promo code", "Shell petrol" pass); both sides keep the same lists, tested in `test/agent/agent_guard_test.dart` and `finn-backend/tests/agent-guardrails.test.ts`.
- **Limits** (`AgentConfig`): message ≤ 2,000 characters; output ≤ 700 tokens; one retry after an outage/timeout and one after unusable output; rate-limit waits ≤ 60 s each and 150 s per turn; at most 3 waves; ≤ 12 ops per plan.

## Agent history

- **Write.** `RemotePlanGateway.execute` sends `history: {runId, request, notes, labels}` with `POST /plans/execute`. The server builds the entry from its own step reports (status, preview summary, record ids, failure message) into `agent_runs`. A retry or a second wave with the same `runId` updates the same row, so there are no duplicate entries and no extra request. Turns that only asked or answered a question write nothing.
- **Read.** `GET /agent/history?limit&before&status` (paginated, filterable) for the History sheet and for history questions; `DELETE /agent/history` clears it.
- **Not context.** History is never sent to the model. Follow-ups ("make that 400", "undo that") use `AgentMemory`: the last 5 saved changes by reference (`#1` = newest) and the one open question, about 100–250 tokens at most.
- Entries keep the request (≤ 500 characters), statuses, summaries and record ids, not copies of records. Owner-only (RLS), kept 180 days, deleted with the account.

## Measured results

Live, `gpt-6-luna` at `none`, demo data, all changes approved, 2026-10-13 (`test/agent/live/plan_benchmark_test.dart`; raw numbers in `docs/agent-benchmarks/`). The baseline is the previous tool-loop agent on the same 13 requests (commit `fc23482`).

| 13 requests | Before (tool loop) | After (single plan) | Change |
|---|---|---|---|
| Correct | 12 / 13 | 13 / 13 | "add 2000 to my Japan trip goal" now resolves |
| Model requests | 26 | 14 | −46% |
| Input tokens (of which cached) | 53,728 (43,164) | 22,510 (20,636) | −58% |
| Cache-write tokens | 10,486 | 0 (prefix already cached) | −100% |
| Output tokens | 1,244 | 531 | −57% |
| Cost as billed | $0.00237 | $0.00066 | −72% |
| Cost with no cache hits | $0.00600 | $0.00252 | −58% |
| Model time (sum) | 51.9 s | 27.4 s | −47% (median per call 2.0 s in both) |
| FiNN API requests (remote mode) | 49 | 36 | multi-op turns 9 → 3 |

Model latency varies between runs: a second run of the new agent made while another benchmark was calling OpenAI took 58.7 s for the same 13 requests (same call and token counts). A cold cache adds one cache write of the 1,474-token prefix (about $0.00018) every 30 minutes of inactivity, shared by all users.

Per request: the 3-operation example went from 1 call / 9 API requests to 1 call / 3 API requests (one preview, one execute, one sync); a settlement 2 → 1 calls; "spent 250 on an auto and Karan paid back 1,200" 3 → 1; "create Pets and add 500" 4 → 1; a spending question 2 → 1; "make that 400" 4 → 2 (one per turn). Extra checks on the new agent: history and balance questions 0 calls; an ambiguous settlement followed by "the concert one" and a missing amount followed by "350" 1 call each in total (17 / 17 correct). Backend latency was not measured over the network; in remote mode every multi-op turn now makes 2–3 requests instead of 2N+1.

## Voice input

**Engine.** Groq Whisper `whisper-large-v3`. It was chosen as the most accurate speech-to-text that is freely available: about 10.3% WER per Groq's docs, against 12% for `-turbo`. It is multilingual (English, Hindi and Hinglish auto-detected) and on Groq's free tier (about 20 requests per minute, 2,000 per day and 28,800 audio-seconds per day). It reuses the server-held Groq key, so nothing new ships in the app. A fixed finance vocabulary prompt (₹, lakh, UPI, EMI, Swiggy…) improves spelling.

**App side** (`lib/agent/voice/`):
- `RecordVoiceCapture` (package `record`) streams 16 kHz mono 16-bit PCM and wraps it as WAV in memory. That is Whisper's native input, so no quality is lost to compression, and no temp files are needed on Android, iOS or web.
- `VoiceInputController` handles tap to talk. Recording stops when the user taps ✓, after 1.8 s of silence once speech was heard, or at 60 s. Clips under 0.5 s are dropped.
- The transcript is sent straight to the agent. If the user had typed something, it is appended to the input instead. Every change still goes through the review panel.
- `FinnRelayTranscriber` posts to the endpoint below.
- Permissions: Android `RECORD_AUDIO` and iOS `NSMicrophoneUsageDescription`.

`POST /api/v1/agent/transcriptions` turns a short recording into text for the assistant input. It uses the same session auth and Groq key as the relay.

Request:

```json
{ "audio": "<base64>", "mimeType": "audio/m4a", "language": "en" }
```

- `audio`: base64 of the recording, at most 10 MB decoded (the body cap is about 14 MB). Empty or invalid base64 is a `validation` error.
- `mimeType`: one of `audio/mp4`, `audio/m4a`, `audio/aac`, `audio/webm`, `audio/ogg`, `audio/wav`, `audio/mpeg`, `audio/flac`.
- `language`: optional 2-letter ISO-639-1 code. Without it the server uses `GROQ_STT_LANGUAGE`, else Whisper auto-detects (English, Hindi, Hinglish).

Response (`data`): `{ "text": string, "language": string | null, "durationSeconds": number | null }`. `text` is trimmed and is `""` when no speech was found, so the app can show "Didn't catch that".

Errors use the relay's shapes: `unavailable` with `details.reason` `rateLimited` (with `retryAfterSeconds`), `providerRateLimited`, `timeout`, `network` or `notConfigured`, and `validation` with `details.reason: tooLarge`. Audio and transcript text are never logged or stored.


## Adding an operation

1. The operation exists as a `FinancialAction` in its feature module (and the matching server action), so forms and the agent share validation and previews.
2. Add an `OpSpec` to `opCatalog` (`plan/op_catalog.dart`): the op type, the action id(s) it may produce, and a compile function that resolves the op's fields into the action's input (use `resolvers.dart`; return `OpQuestion` for missing essentials, `OpRejected` for impossible ones).
3. Add one line for it under TYPES in `agentInstructions` (`prompt/agent_prompt.dart`). `test/agent/plan_test.dart` fails if the catalog and the instructions disagree, and compiles a sample of every op against real data and the real action decoder.
4. Read-only answers go in `answers/data_answers.dart`.

## Replacing the LLM provider

The boundary is `LlmProvider` (`lib/agent/llm/llm_provider.dart`), with neutral types: instructions, messages, `LlmOutputFormat.json`, usage. The plan format, op catalog, execution, history and UI do not depend on the vendor.

- **Another OpenAI-compatible Chat Completions provider:** change `OPENAI_BASE_URL`, `OPENAI_MODEL` and the key on the server. Set `OPENAI_PROMPT_CACHE=implicit` if it does not support explicit cache breakpoints.
- **A different wire format:** write a new `LlmProvider` (encode/decode like `ChatCompletionsProvider`, mapping `LlmOutputFormat.json` to that provider's JSON mode), point the relay at it, and override `llmProviderProvider` in `lib/agent/application/agent_providers.dart`.

## Tests

`test/agent/`:
- `agent_runner_test.dart`: the three-operation example in one model call, one review and one backend round; repeated op types; local settlement matching; dependent ops in a second wave; skipped dependants; clarification with options answered locally; missing amount completed locally; clear ops proceeding next to a question; an unclear answer sent to the model with context; generic people; invalid model output (retry, then a safe message); unknown op types; preview failures; partial success; a lost reply followed by an idempotent replay; deliberate repeats; identical ops in one message; decline; stop; model outages; grounding of methods and shops; data, history and balance answers without extra calls; that the model never sees records or history; "make that 400"; "undo that"; the user's time zone.
- `plan_test.dart`: parser rules, amount/date/method/name resolvers, catalog ↔ instructions consistency, a compiled sample of every op previewed by its real action, questions and rejections, local intents.
- `plan_gateway_test.dart`: `/plans/preview` and `/plans/execute` contract, outcome mapping, history payload, one idempotent retry, "not confirmed" when the retry fails, the history repository and `historyAnswer`.
- `chat_completions_provider_test.dart`: JSON-mode wire format, usage details, refusals, relay error mapping, cancellation.
- `agent_screen_test.dart`, `voice_test.dart`, `test/journeys/agent_mode_journey_test.dart`: controller, review flow, history sheet (list, expand, filter, clear), voice, navigation.
- `live/plan_benchmark_test.dart` (skipped unless `FINN_LIVE=1`): calls OpenAI with the key from `finn-backend/.env.local` and writes `docs/agent-benchmarks/single_plan.json`.

Backend: `tests/agent-relay.test.ts` (response formats, cache breakpoint, usage details) and `tests/agent-history.test.ts` (history from real outcomes, retries without duplicates, partial and declined turns, second waves, pagination, filters, isolation, clearing).

## Known limits

- Requests that need more than 12 operations, or more than 3 rounds of dependencies, are cut short with a message.
- Fixed-offset time zones only (India and similar); for zones with daylight saving the device's date is used.
- History questions are matched by a few narrow phrases; other wordings reach the model, which returns a `history` op (one call).
- The agent cannot delete records, edit the profile or share pending items with other FiNN users.
- Loan creation needs every term in the message (amount, rate, EMIs, first due date, lender); otherwise the agent asks for them.
