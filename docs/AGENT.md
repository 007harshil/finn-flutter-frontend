# FiNN assistant (agent module)

The assistant turns natural-language requests into real record-keeping operations. For example: "spent 450 on lunch and Rahul paid back the 2,000". It works through LLM tool calling. Every write goes through the existing action layer, and in remote mode through the FiNN API, only after the user approves the app's own preview of it.

Code: `lib/agent/`. Tests: `test/agent/`. Backend relay: `finn-backend` `POST /api/v1/agent/completions`.

## Setup

1. **Backend** (`finn-backend`, env vars; the API boots without them):

   | Variable | Default | Purpose |
   |---|---|---|
   | `GROQ_API_KEY` | (unset = "not configured") | Groq key. **Server only**: keep it in `.env.local` (git-ignored) locally and in the host's secret settings in production. Never put it in the app or in git. |
   | `GROQ_MODEL` | `openai/gpt-oss-20b` | Model for every request |
   | `GROQ_FALLBACK_MODELS` | `openai/gpt-oss-120b` | Comma-separated models tried in order when the model before them is rate limited (429/498). Groq meters each model separately, so each fallback adds its own per-minute budget. They get the same request, including `reasoning_effort`. `none` disables fallback. |
   | `GROQ_REASONING_EFFORT` | `low` | `off` (param not sent) \| `none` \| `default` \| `low` \| `medium` \| `high` |
   | `GROQ_BASE_URL` | `https://api.groq.com/openai/v1` | Chat Completions at `/chat/completions` |
   | `GROQ_TIMEOUT_MS` | `60000` | Upstream timeout (the route's `maxDuration` is 75 s) |
   | `AGENT_MAX_OUTPUT_TOKENS` | `2048` | Cap on `max_completion_tokens` |
   | `AGENT_RATE_LIMIT_PER_MINUTE` / `AGENT_DAILY_REQUEST_LIMIT` | `20` / `300` | Per-user limits, kept in memory on each server instance |
   | `GROQ_STT_MODEL` | `whisper-large-v3` | Speech-to-text model (voice input) |
   | `GROQ_STT_LANGUAGE` | (unset = auto-detect) | Default ISO-639-1 language for voice input |
   | `GROQ_STT_PROMPT` | finance vocabulary hint | Whisper `prompt` for spelling of rupee/UPI/EMI/merchant terms |
   | `GROQ_STT_TIMEOUT_MS` | `30000` | Transcription timeout (the route's `maxDuration` is 45 s) |
   | `AGENT_STT_RATE_LIMIT_PER_MINUTE` / `AGENT_STT_DAILY_LIMIT` | `10` / `200` | Per-user transcription limits, separate from the completions limits, in memory per instance |

2. **App:** run in remote mode (`--dart-define=FINN_API_URL=...`). In local mock mode the assistant screen says it is unavailable, because there is nowhere safe to hold the key. Open the assistant from the agent orb in the centre of the bottom navigation bar, between Budgets and Goals. On wide screens it sits at the top of the navigation rail. `AppRoutes.assistant` still opens the same console full screen, for deep links.

## Agent mode and the review UI

- **Entry point.** The orb (`AgentOrb`, `presentation/widgets/agent_logo.dart`) uses FiNN's own mark: a fin riding a wave, with a spark, inside an emerald → cyan → indigo orb. The colours are `FinnColors.agentStart/Mid/End`. The orb sits raised at the true centre of the bar: three tabs share the left half and two share the right. When idle it plays an attention burst (rotating gradient ring, pulse halo, flowing wave) for 2 loops, about 12 s. The burst runs when it appears and again on every tab switch, then the orb rests. In agent mode or while listening it animates continuously. Reduced motion shows the static mark.
- **Agent mode** (`agentModeProvider`). Tapping the orb opens `AgentModePanel` over the app. Everything behind the panel is blurred, dimmed, and excluded from input, focus and semantics. The tabs and the add-transaction button are disabled. Tapping the orb (labelled "Close"), the panel's ✕, or Back exits agent mode. Exiting also cancels any open microphone, and signing out always exits.
- **Review before changes.** `ChangeReviewPanel` (`widgets/change_review.dart`) replaces the old text card:
  - Header impact tiles: number of changes, how many move money, and how many are permanent or how many areas they touch.
  - One card per change: a module icon and colour, a "MODULE · VERB" eyebrow, the app's own summary, the amount in large type, and detail chips.
  - Before → after strips for preview lines such as `Available to spend ₹10,000 → ₹9,550`, plus *Moves money* / *Cannot be undone* pills and warnings.
  - Each card can be excluded on its own. Nothing is written until **Approve**.
- **Final summary.** `OutcomeSummary` (`widgets/outcome_summary.dart`) shows "All N changes saved", "X of N saved" or "No changes made", with a segmented status bar (one segment per change) and a row per change with its real dispatcher status.

### Model choice

`openai/gpt-oss-20b` is the default. It is a production model on Groq, available on the free tier, lightweight and built for tool use, and it is the cheapest Groq model that supports tool calling. For better accuracy on complex requests, set `GROQ_MODEL=openai/gpt-oss-120b`; it has the same limits and API. Both make one tool call per step (no parallel calls). Several actions therefore go into one `queue_actions` call (see below) instead of one step each.

Groq's free tier allows about **8,000 tokens per minute** per model, and every step resends the whole request (about 2.5k tokens). The module is designed around that limit:
- **One call for many actions.** `queue_actions` carries every action of a message. With `done: true` the runner opens the review card straight away, without a closing model call.
- Tools load in groups (see below), and the instructions and schemas are compact.
- One review card per turn. The final report is built from the confirmed outcomes without another model call.
- **Fallback model.** When the main model is rate limited, the relay sends the same request to `GROQ_FALLBACK_MODELS` at once. A model that was just rate limited is skipped until its `retry-after` passes.
- **Quiet pacing.** If every model is rate limited, the app waits for the requested time and carries on. It shows "Still working on it…", not an error. A single wait may last up to 60 s, and all waits in one turn together up to 150 s. Only a longer wait, such as a daily limit, ends the turn with a message.

Live checks (2026-10-13, `gpt-oss-20b`):

| Request | Before | Now |
|---|---|---|
| "bought vegetables of 70rs, milk of 150rs, petrol 400, added netflix premium 179 yesterday" | 10 calls, about 15.6k tokens, 4 rate-limit waits, 72 s | 1 call, about 2.9k tokens, no waits, 4 actions on one card (4 of 4 runs) |
| "Rahul paid back the 2000 and I spent 300 on an auto" | 4 calls, about 6.6k tokens | 2 calls (lookup, then batch), about 4.4k tokens |
| "Create a category called Pets and record 500 on dog food in it" | stopped after the category; the expense was dropped | 3 calls, 2 review cards, both saved |

The free tier also has a **daily** cap per model (about 200k tokens and 1,000 requests for `gpt-oss-20b`). When it is reached, Groq asks for a wait of many minutes. The relay then serves from the fallback model, which has its own daily cap, until the main model is available again.

## How a request flows

```
AgentScreen ──send──▶ AgentController ──▶ AgentRunner
                                              │  LlmRequest (provider-neutral)
                                              ▼
                                         LlmProvider ── GroqChatProvider ──▶ FinnRelayTransport (ApiClient, user's session)
                                              │                                   ▼
                                              │                    FiNN API relay (adds key, model) ──▶ Groq /chat/completions
                                              │  tool calls
                                              ▼
                                         ToolExecutor
                                           ├─ read tools ──▶ FinanceSnapshot (data the app already synced)
                                           └─ action tools ──▶ validate + preview ──▶ queue
                                                                                   │ (model finished)
                                                       ApprovalCard (all queued) ◀─┘
                                                              ▼ approved
                                                       OperationDispatcher (channel: agent, fingerprint, idempotency key)
                                                       → RemoteOperationDispatcher → POST /actions/{id}
```

1. **Plan.** The model calls tools. Lookups run immediately. Actions usually arrive together in one `queue_actions` call, though a direct action tool call works too. Each action is checked: unknown tools and malformed JSON are rejected, arguments are pruned to the tool's schema, the action's own `decode` runs, and the dispatcher previews it on fresh data. A valid action is *queued*. The model is told it is not done yet. In a batch, each item is checked on its own: valid items stay queued, and the model resends only the failed ones, fixed.
2. **Review.** When the model marks its batch `done: true` and every item is valid, or when it replies with text, every queued action appears on **one** review card. The user can approve all, approve some or decline. Client and server policy require confirmation for every agent action and forbid deletes.
3. **Execute.** Approved actions run through `dispatch` with the preview's fingerprint. If a record changed after review, the action is not written and is reported as `needsReapproval`.
4. **Report.** Outcome rows (Saved, Not approved, Failed, Not confirmed) and the reply text come from the dispatcher's results, never from the model. The outcomes are also added to the conversation as an app message.
5. **Dependent steps.** When a later action needs an earlier result (for example a new category's id), the model ends its plan with `[continue]`. After approval it receives the outcomes, including record ids, and can propose the rest. That goes through the review card again.
   - gpt-oss often forgets the marker, or puts a placeholder id in the dependent item. If any action was refused in the turn and never fixed, the runner continues after the review anyway, once per turn. It then asks the model to queue what is still missing, using the new record ids. The model's text is not shown above the card in that case, because it usually asks the user for the id the app is about to supply.
6. **Tool calls written as text.** gpt-oss sometimes writes a tool call as JSON in its reply instead of calling the tool. When the whole reply is such a call to an offered tool, for example `{"queue_actions": {...}}` or `{"name": ..., "arguments": {...}}`, the runner treats it as a real call. It then goes through the same validation and review.

## Tools

Offered in groups to keep requests small. Core is always offered. Other groups are switched on by keywords in the message ("EMI", "budget", "Netflix", "split"…) or by the model calling `load_tools`, and they stay on for the conversation.

| Group | Tools | Maps to |
|---|---|---|
| core | `get_financial_overview`, `find_records`, `search_transactions`, `load_tools` | read-only lookups over the synced snapshot (`find_records` uses `PendingResolver` rules: unique / multiple / none) |
| core | `queue_actions` | up to 12 `{tool, arguments}` items, each any action tool below, plus `done`. Each item gets the same checks as a direct call and switches on its tool's group. |
| core | `record_transaction`, `add_pending_payment`, `settle_pending_payment` | `transactions.create`, `pending.create`, `pending.settle` |
| edits | `edit_transaction`, `create_category` | `transactions.update`, `categories.create` |
| budgets | `create_budget`, `update_budget`, `pause_or_resume_budget` | `budgets.create/update/setPaused` |
| pending | `split_bill`, `write_off_pending_payment` | `pending.split/cancel` |
| loans | `record_loan_payment`, `create_loan` | `loans.recordPayment/create` |
| subscriptions | `add_subscription`, `mark_subscription_paid`, `set_subscription_status`, `skip_subscription_cycle` | `subscriptions.*` |
| goals | `create_goal`, `contribute_to_goal`, `withdraw_from_goal` | `goals.create/contribute/withdraw` |
| emergencyFund | `add_to_emergency_fund`, `withdraw_from_emergency_fund` | `emergencyFund.contribute/withdraw` |

Not exposed: every `*.delete` (policy blocks these too), profile and asset edits, and sharing pending items with other FiNN users (`linkedUserId` is hidden).

## Safety properties

- **No direct data access.** Read tools use the `FinanceSnapshot` built from API-synced records. Writes go only through the dispatcher, so in remote mode they reach `POST /actions/{id}`, where the server validates and authorises them. The agent never holds database or provider credentials.
- **Model output is untrusted.** It passes schema pruning, then the action's decoder (crashes are caught), then `prepare`, then the server's own validation.
- **No fake success.** Only `ActionCompleted` counts as saved, and the report text and rows are built from dispatcher outcomes.
- **Duplicates.** The idempotency key is `agent:<conversation>:<request fingerprint>:<occurrence>`.
  - Identical calls in one turn are queued once.
  - Retrying after an unknown outcome (a lost reply) reuses the key, so the server replays the stored result instead of writing twice.
  - A deliberate identical entry in a later turn gets a new key and a "possible duplicate" note on the card.
  - Known edge: if an outcome was unknown and the user then asks for a separate identical entry, the server replays the first one ("Already saved"). Repeating the request again records it, because the next occurrence gets a new key.
- **No automatic retries of mutations.** Model calls are retried only after a timeout, an outage, a malformed tool call (`toolCallFailed`) or a rate-limit wait that fits the turn's budget.
- **Partial success.** Each action commits on its own. Each outcome is reported separately.
- **Prompt injection.** The instructions treat record text and tool results as data. Any write still needs approval of the app-generated preview.
- **Limits** (`AgentConfig`):
  - 10 model calls per turn; the last one forces `tool_choice: none`.
  - 8 tool calls per step and 24 per turn. A `queue_actions` call counts as one and holds up to 12 actions.
  - Rate-limit waiting: at most 60 s per wait and 150 s per turn (`maxRateLimitWait`, `rateLimitWaitBudget`).
  - Messages up to 2,000 characters.
  - History limited to 6 turns, about 12k characters and at most 180 provider items.
  - Tool results truncated at 3,000 characters.

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

## Context and memory

The conversation lives in memory for the app session. It is cleared on sign-out, on an account switch or with "New chat". Pending approvals are never persisted, so an interrupted session can never execute anything later. Financial data is fetched fresh through tools and is not stored in the conversation. There is no long-term memory, vector store or RAG.

## Adding a tool

- **Expose an existing action:** add an entry to `agentActionTools` (`lib/agent/tools/tool_catalog.dart`) and assign it a group in `toolGroupOf` (`tool_groups.dart`); core is the default. The schema comes from the action's `ActionFieldSpec`s. Use `_fieldOverrides` for coarse fields such as lists and `_excludedFields` for fields the agent must not set.
- **New operation:** first create a `FinancialAction` in its feature module, plus the matching server action, so forms and the agent share it. Then expose it as above.
- **New lookup:** subclass `ReadTool` (`read_tools.dart`) and add it to `AgentToolbox.standard`. Keep results compact and include ids and versions.
- Add tests to `test/agent/tool_executor_test.dart`, and to `agent_runner_test.dart` (using `ScriptedProvider`) for multi-step behaviour.

## Replacing the LLM provider

The boundary is `LlmProvider` (`lib/agent/llm/llm_provider.dart`). It uses neutral types: messages, tool specs and tool calls, plus an opaque `providerState` that a provider can use for exact replay.

- **Another OpenAI-compatible Chat Completions provider** (for example OpenAI, Together or a self-hosted vLLM): change `GROQ_BASE_URL`, `GROQ_MODEL` and the key on the server. No app change is needed (the env names would just read oddly).
- **A different wire format:** write a new `LlmProvider` (encode and decode like `GroqChatProvider`). Point the relay at that provider, or add a second relay route, and override `llmProviderProvider` in `lib/agent/application/agent_providers.dart`. Tools, executor, runner and UI stay unchanged.

## Tests

`test/agent/`:
- `groq_provider_test.dart`: wire format against the relay contract, the token budget of an opening request, decoding, error mapping and cancellation.
- `tool_executor_test.dart`: tool groups, validation, pruning, the queue and the single approval card, decline, duplicates, stale approval, a lost reply followed by a safe retry, limits and read tools.
- `agent_runner_test.dart`: multi-action flow with sequential calls, ambiguity, partial approval, dependent follow-up via `[continue]`, unsupported operations, rate-limit waits, failures, loop limits, cancellation and context.
- `agent_screen_test.dart`: the controller (duplicate submit, stop, retry) and the screen (approve flow, unavailable state).
- `voice_test.dart`: WAV encoding, levels, the voice controller (permission, short clips, failures, cancel, agent-mode close) and a spoken request through the review panel.
- `test/journeys/agent_mode_journey_test.dart`: the orb is centred after Budgets, agent mode locks tabs and the add button, and closing restores them.

These use scripted model responses. The live check against Groq described above was run manually with a temporary test that is not part of the suite.
