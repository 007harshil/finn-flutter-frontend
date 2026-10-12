# FiNN assistant (agent module)

The assistant turns natural-language requests into real record-keeping operations. For example: "spent 450 on lunch and Rahul paid back the 2,000". It works through LLM tool calling. Every write goes through the existing action layer, and in remote mode through the FiNN API, only after the user approves the app's own preview of it.

Code: `lib/agent/`. Tests: `test/agent/`. Backend relay: `finn-backend` `POST /api/v1/agent/completions`.

## Setup

1. **Backend** (`finn-backend`, env vars; the API boots without them):

   | Variable | Default | Purpose |
   |---|---|---|
   | `GROQ_API_KEY` | (unset = "not configured") | Groq key. **Server only**: keep it in `.env.local` (git-ignored) locally and in the host's secret settings in production. Never put it in the app or in git. |
   | `GROQ_MODEL` | `openai/gpt-oss-20b` | Model for every request |
   | `GROQ_REASONING_EFFORT` | `low` | `off` (param not sent) \| `none` \| `default` \| `low` \| `medium` \| `high` |
   | `GROQ_BASE_URL` | `https://api.groq.com/openai/v1` | Chat Completions at `/chat/completions` |
   | `GROQ_TIMEOUT_MS` | `60000` | Upstream timeout (the route's `maxDuration` is 75 s) |
   | `AGENT_MAX_OUTPUT_TOKENS` | `2048` | Cap on `max_completion_tokens` |
   | `AGENT_RATE_LIMIT_PER_MINUTE` / `AGENT_DAILY_REQUEST_LIMIT` | `20` / `300` | Per-user limits, kept in memory on each server instance |

2. **App:** run in remote mode (`--dart-define=FINN_API_URL=...`). In local mock mode the assistant screen says it is unavailable, because there is nowhere safe to hold the key. Open the assistant from the sparkle button in the Home header (`AppRoutes.assistant`).

### Model choice

`openai/gpt-oss-20b` is the default. It is a production model on Groq, available on the free tier, lightweight and built for tool use, and it is the cheapest Groq model that supports tool calling. For better accuracy on complex requests, set `GROQ_MODEL=openai/gpt-oss-120b`; it has the same limits and API. Both make one tool call per step (no parallel calls), so the agent works step by step.

Groq's free tier allows about **8,000 tokens per minute and 30 requests per minute** per model. The module is designed around that limit:
- Tools load in groups (see below), and the instructions and schemas are compact. An opening request is about 1.6k tokens.
- One review card per turn. The final report is built from the confirmed outcomes without another model call.
- If Groq asks the app to wait, it waits (up to 60 s, twice) and shows "The assistant is busy. Retrying in N s".

A live check of "Rahul paid back the 2000 and I spent 300 on an auto" took 4 model calls and about 6.6k tokens, with both actions saved after one approval.

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

1. **Plan.** The model calls tools. Lookups run immediately. Each action call is checked: unknown tools and malformed JSON are rejected, arguments are pruned to the tool's schema, the action's own `decode` runs, and the dispatcher previews it on fresh data. A valid action is *queued*. The model is told it is not done yet.
2. **Review.** When the model replies with text, every queued action appears on **one** review card. The user can approve all, approve some or decline. Client and server policy require confirmation for every agent action and forbid deletes.
3. **Execute.** Approved actions run through `dispatch` with the preview's fingerprint. If a record changed after review, the action is not written and is reported as `needsReapproval`.
4. **Report.** Outcome rows (Saved, Not approved, Failed, Not confirmed) and the reply text come from the dispatcher's results, never from the model. The outcomes are also added to the conversation as an app message.
5. **Dependent steps.** When a later action needs an earlier result (for example a new category's id), the model ends its plan with `[continue]`. After approval it receives the outcomes, including record ids, and can propose the rest. That goes through the review card again.

## Tools

Offered in groups to keep requests small. Core is always offered. Other groups are switched on by keywords in the message ("EMI", "budget", "Netflix", "split"…) or by the model calling `load_tools`, and they stay on for the conversation.

| Group | Tools | Maps to |
|---|---|---|
| core | `get_financial_overview`, `find_records`, `search_transactions`, `load_tools` | read-only lookups over the synced snapshot (`find_records` uses `PendingResolver` rules: unique / multiple / none) |
| core | `record_transaction`, `add_pending_payment`, `settle_pending_payment` | `transactions.create`, `pending.create`, `pending.settle` |
| transactions | `edit_transaction`, `create_category` | `transactions.update`, `categories.create` |
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
- **No automatic retries of mutations.** Model calls are retried only after a timeout, an outage, a malformed tool call (`toolCallFailed`) or a short rate-limit wait.
- **Partial success.** Each action commits on its own. Each outcome is reported separately.
- **Prompt injection.** The instructions treat record text and tool results as data. Any write still needs approval of the app-generated preview.
- **Limits** (`AgentConfig`):
  - 10 model calls per turn; the last one forces `tool_choice: none`.
  - 8 tool calls per step and 24 per turn.
  - Messages up to 2,000 characters.
  - History limited to 6 turns, about 12k characters and at most 180 provider items.
  - Tool results truncated at 3,000 characters.

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

These use scripted model responses. The live check against Groq described above was run manually with a temporary test that is not part of the suite.
