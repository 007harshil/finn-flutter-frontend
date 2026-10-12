# FiNN assistant (agent module)

The assistant turns natural-language requests ("spent 450 on lunch and Rahul paid back the 2,000") into real record-keeping operations. It uses LLM tool calling. Every write goes through the existing action layer and, in remote mode, the FiNN API, and only after the user approves the app's own preview of it.

Code: `lib/agent/`. Tests: `test/agent/`. Backend relay: `finn-backend` `POST /api/v1/agent/completions`.

## Setup

1. **Backend** (`finn-backend`, env vars; the API boots without them):

   | Variable | Default | Purpose |
   |---|---|---|
   | `XAI_API_KEY` | (unset, so the assistant is "not configured") | xAI key. Server only. Never put it in the app. |
   | `XAI_MODEL` | `grok-4.3` | Model used for every request |
   | `XAI_REASONING_EFFORT` | `low` | `none` \| `low` \| `medium` \| `high` |
   | `XAI_BASE_URL` | `https://api.x.ai/v1` | Provider base URL (Responses API at `/responses`) |
   | `XAI_TIMEOUT_MS` | `60000` | Upstream timeout (route `maxDuration` is 75 s) |
   | `AGENT_MAX_OUTPUT_TOKENS` | `2048` | Cap on `max_output_tokens` |
   | `AGENT_RATE_LIMIT_PER_MINUTE` / `AGENT_DAILY_REQUEST_LIMIT` | `20` / `300` | Per-user limits. In memory, per server instance. |

2. **App**: run in remote mode (`--dart-define=FINN_API_URL=...`). In local mock mode the assistant screen says it is unavailable, because there is no secure place for the key. Open it from the sparkle button in the Home header (route `AppRoutes.assistant`).

## How a request flows

```
AgentScreen ──send──▶ AgentController ──▶ AgentRunner (loop, ≤ 8 model calls)
                                              │  LlmRequest (neutral)
                                              ▼
                                         LlmProvider ── GrokResponsesProvider ──▶ FinnRelayTransport
                                              │                                   (ApiClient, user's session)
                                              │                                        ▼
                                              │                          FiNN API relay ──▶ xAI /v1/responses
                                              │  tool calls
                                              ▼
                                         ToolExecutor
                                           ├─ read tools ──▶ FinanceSnapshot (data the app already synced)
                                           └─ action tools ──▶ OperationDispatcher (channel: agent)
                                                 preview ──▶ ApprovalCard ──▶ dispatch with fingerprint
                                                                               (RemoteOperationDispatcher
                                                                                → POST /actions/{id})
```

1. The runner sends the instructions (rules, today's date, the category list), the windowed conversation and the tool schemas.
2. For each tool call, the executor rejects unknown tools and malformed JSON. It prunes the arguments to the tool's schema, decodes them with the action's own `decode` and previews them with the dispatcher on fresh data. Read tools run at once.
3. All action proposals from one model step appear together on one review card. The user can approve all of them, approve some or decline. The app's default policy, enforced on the server too, requires confirmation for every agent action and forbids deletes from the agent channel.
4. Approved actions run through `dispatch` with the preview's fingerprint. If the record changed after review, the fingerprint no longer matches and the action is reported as `needsReapproval` without being written.
5. The tool results (the real outcomes) go back to the model, which continues or answers. The reply is shown together with an outcome row per action taken from the dispatcher (Saved, Not approved, Failed, Not confirmed), never from the model's text.

## Tools

| Tool | Kind | Maps to |
|---|---|---|
| `get_financial_overview` | read | balances, budget month, budgets, pending totals, debt, subscriptions due, emergency fund |
| `find_records` | read | pending (unique / multiple / none match via `PendingResolver`), goals, budgets, loans, subscriptions |
| `search_transactions` | read | filter by text, type, category, dates, amount; totals |
| `record_transaction`, `edit_transaction` | action | `transactions.create`, `transactions.update` |
| `create_category` | action | `categories.create` |
| `create_budget`, `update_budget`, `pause_or_resume_budget` | action | `budgets.create/update/setPaused` |
| `add_pending_payment`, `split_bill`, `settle_pending_payment`, `write_off_pending_payment` | action | `pending.create/split/settle/cancel` |
| `record_loan_payment`, `create_loan` | action | `loans.recordPayment/create` |
| `add_subscription`, `mark_subscription_paid`, `set_subscription_status`, `skip_subscription_cycle` | action | `subscriptions.*` |
| `create_goal`, `contribute_to_goal`, `withdraw_from_goal` | action | `goals.create/contribute/withdraw` |
| `add_to_emergency_fund`, `withdraw_from_emergency_fund` | action | `emergencyFund.contribute/withdraw` |

Not exposed: every `*.delete` (also blocked by policy), profile and asset edits, and sharing pending items with other FiNN users (`linkedUserId` is hidden, because the agent has no people-directory tool).

## Safety properties

- **No direct data access.** Read tools use the `FinanceSnapshot` that the app builds from API-synced records. Writes use the dispatcher, so in remote mode they go to `POST /actions/{id}`, where the server validates and authorizes them. The agent never holds DB or provider credentials.
- **Untrusted model output.** Schema pruning, then the action's decoder, then the action's `prepare`. The server validates again.
- **No fake success.** A result is "completed" only when the dispatcher returns `ActionCompleted`. The instructions forbid claiming anything else, and the UI shows dispatcher outcomes.
- **Duplicates.** The idempotency key is `agent:<conversation>:<request fingerprint>:<occurrence>`.
  - Identical calls in one step run once.
  - Repeating a completed request in the same turn returns `alreadyHandled`.
  - Retrying after an unknown outcome (a lost reply) reuses the key, so the server replays the result instead of writing twice.
  - A deliberate identical entry in a later turn gets a new key and a "possible duplicate" note on the card.
  - Known edge: if a write's outcome was unknown and the user then asks for a separate identical entry, the reused key makes the server replay the first one ("Already saved"). The next identical request gets a new key, so repeating it records the second entry.
  - Two identical entries in one request are recorded once; the model is told to add a distinguishing note if the user really meant two.
- **No automatic retries of mutations.** Only model calls are retried, once, after a timeout or outage. Rate limits are never retried.
- **Partial success.** Each action commits on its own (no cross-action transaction). The outcome of each one is reported.
- **Prompt injection.** The instructions treat record fields and tool results as data. Even so, any write still needs the user's approval of the app-generated preview.
- **Limits.** 8 model calls per turn (the last one forces `tool_choice: none`), 8 tool calls per step, 24 per turn, 2,000-character messages, and history windowed to 8 turns, about 48k characters and ≤ 180 provider items (`AgentConfig`).

## Context and memory

The conversation (`Conversation`) is in memory for the app session. It clears on sign-out, when the user switches accounts or when the user taps "New chat". Pending approvals are never persisted, so an interrupted session cannot execute anything later. Financial data is not stored in the conversation; tools fetch it fresh. There is no long-term memory, vector store or RAG.

## Adding a tool

- **Expose an existing action:** add one entry to `agentActionTools` in `lib/agent/tools/tool_catalog.dart`. The schema comes from the action's `ActionFieldSpec`s. Add `_fieldOverrides` for fields whose spec is too coarse (lists), and `_excludedFields` for fields the agent must not set.
- **New operation:** first create a `FinancialAction` in its feature module (and the matching server action) so forms and the agent share it. Then expose it as above.
- **New lookup:** subclass `ReadTool` (`lib/agent/tools/read_tools.dart`) and add it to `AgentToolbox.standard`. Keep results compact and include ids and versions.
- Add tests in `test/agent/tool_executor_test.dart` (executor on `ActionHarness`) and, for multi-step behaviour, in `agent_runner_test.dart` with `ScriptedProvider`.

## Replacing the LLM provider

The boundary is `LlmProvider` (`lib/agent/llm/llm_provider.dart`), which uses neutral types: messages, tool specs, tool calls and an opaque `providerState` for exact replay.

- **Another Responses-compatible endpoint:** change `XAI_BASE_URL`, `XAI_MODEL` and the key on the server. No app change.
- **A different wire format:** write a new `LlmProvider` (encode/decode like `GrokResponsesProvider`), and point the relay at that provider or add a second relay route. Then override `llmProviderProvider` in `lib/agent/application/agent_providers.dart`. Tools, executor, runner and UI do not change.

## Tests

`test/agent/`:
- `grok_provider_test.dart`: wire format against the relay contract, reasoning replay, decoding, error mapping, timeout, cancellation.
- `tool_executor_test.dart`: validation, pruning, approval and decline, duplicates, stale approval, lost reply plus safe retry, limits, read tools.
- `agent_runner_test.dart`: multi-action flow, ambiguity, partial success, self-correction, unsupported operations, provider failures, loop limits, cancellation, context.
- `agent_screen_test.dart`: controller (duplicate submit, stop, retry) and the screen (approve flow, unavailable state).

All of these use scripted model responses. A live check needs `XAI_API_KEY` on the backend.
