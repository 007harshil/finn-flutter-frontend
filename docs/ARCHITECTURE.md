# Architecture

FiNN is a Flutter app with a layered, feature-first structure. Features never talk to storage directly: they read a derived, immutable snapshot and write through typed actions.

```
 UI (screens, sheets)                       lib/features/<f>/presentation
   │ watch                       ▲ runAction(...)
   ▼                             │
 Riverpod providers         OperationDispatcher          lib/app/di, lib/actions
   │ derive                      │ prepare → confirm → execute
   ▼                             ▼
 FinanceSnapshot + calculators   FinancialAction (per module)   lib/finance, lib/features/<f>/{domain,application}
   ▲ loadSnapshot / streams      │ save / delete
   │                             ▼
 FinanceRepositories (interfaces)                         lib/domain
   ▲ implemented by
 LocalDataStore (mock backend: EntityCollection + JSON)   lib/data/local, lib/core/persistence
```

## Layers

| Layer | Location | Responsibility |
|---|---|---|
| Core | `lib/core/` | `Money` (int paise) and formatting, calendar dates (`dates.dart`, `frequency.dart`), `Clock`, `IdGenerator`, `Result`/`AppFailure`, persistence primitives. No Flutter widgets. |
| Domain | `lib/features/<f>/domain/`, `lib/finance/` | Immutable models and pure calculators (ledger, budgets, goals, emergency fund, loans, subscriptions, pending, net worth, alerts, analytics, timeline). Deterministic: "today" is always passed in. |
| Contracts | `lib/domain/` | `CrudRepository<T>` / `ValueRepository<T>` per entity, bundled in `FinanceRepositories`. |
| Data | `lib/data/` | Local mock repositories (`local_data_store.dart`), JSON codecs (`dto/dtos.dart`), seed scenarios (`mock/seed_data.dart`). |
| Actions | `lib/actions/`, `lib/features/<f>/application/*_actions.dart` | Every write. See below. |
| App | `lib/app/` | DI providers, go_router configuration, navigation shell. |
| Presentation | `lib/features/<f>/presentation/`, `lib/design_system/`, `lib/shared/presentation/` | Widgets only. No financial logic. |

## Read path: one snapshot

1. Each repository exposes `watchAll()` / `watch()`; `data_providers.dart` turns them into `StreamProvider`s.
2. `financeSnapshotProvider` combines every collection with `todayProvider` and the budget month start day into one `FinanceSnapshot`. It is loading until every collection has emitted and errors if any fails.
3. Every projection (`balanceProvider`, `budgetUsagesProvider`, `netWorthProvider`, `allAlertsProvider`, `insightsProvider`, …) is derived from that snapshot. Inside the snapshot, projections are `late final` (computed once, lazily) and cash-flow summaries are memoised per date range.
4. Any data change produces a new snapshot. Because all figures come from the same instance, the home balance, a budget card and an alert can never disagree.

`todayProvider` rolls over just after midnight, so due dates and "today" projections update without a restart.

## Write path: actions

Every mutation is a `FinancialAction<I, O>` with:

- an `ActionDescriptor` (stable id such as `loans.recordPayment`, module, risk, `movesMoney`, `reversible`, field specs for discovery);
- a typed `ActionInput` with `toJson()` and a `decode(json)` that validates untrusted input via the `In` helpers;
- `prepare(input, snapshot, env)` — validation against a fresh snapshot and an `ActionPreview` (title, one-line summary, detail lines, warnings, fingerprint). It must not mutate anything;
- `execute(input, snapshot, env)` — writes through `env.repos`.

`OperationDispatcher.dispatch` (`lib/actions/dispatcher.dart`) is the only entry point and guarantees:

- **Fresh validation** — a new snapshot is loaded and `prepare` runs immediately before `execute`.
- **Confirmation** — consequential actions (and anything from the agent/voice channels) run only with an `ActionConfirmation` whose fingerprint equals the current preview's. The fingerprint is an FNV-1a hash of the action id and canonical input JSON, plus an optional hash of the record state (`basis`, e.g. version and outstanding amount). If the record changed after review, the fingerprint changes and the user is asked again.
- **Idempotency** — the idempotency key is claimed before the first `await`. A concurrent duplicate is rejected (`duplicate`); a completed one replays its result; reusing a key for a different request is a `conflict`. Failed or rejected attempts release the key so they can be retried. The last 500 keys are remembered (in memory).
- **Policy** — `DefaultActionPolicy`: UI and system channels may run everything; agent and voice must confirm every action and may never run `*.delete`; imports may only run `*.create`.
- **Audit** — every executed attempt (success or failure) is recorded in `AuditLog` with channel, time and who confirmed. It is shown in Settings → Activity log.

The UI uses `runAction(...)` (`lib/shared/presentation/action_runner.dart`): dispatch, show the review sheet when confirmation is needed, re-dispatch with the approval, then toast / haptics / inline field errors. Forms keep one idempotency key per form session, which makes double taps harmless.

Cross-module money movements are created only by actions in their owning module and linked by `TransactionOrigin` + `originRefId` (loan repayments, disbursements, settlements, subscription payments). Linked transactions cannot be edited or deleted from the transactions module, which prevents double counting.

`ActionRegistry` (populated from `lib/app/di/action_catalog.dart`) lists descriptors as JSON and decodes/dispatches by id. `PlanExecutor` (`action_plan.dart`) runs multi-step plans: it previews every step, executes only approved fingerprints, skips steps whose dependencies failed, and reports a step as stale (`staleData`) if its record changed after approval. Steps commit independently; there is no cross-step rollback.

## State management and navigation

- Riverpod 3 without code generation. Core providers (`core_providers.dart`): `localDataStoreProvider` and `sharedPreferencesProvider` (overridden in `main.dart` and tests), `clockProvider`, `idGeneratorProvider`, `todayProvider`, `financeRepositoriesProvider`, `settingsProvider`. Action providers (`action_providers.dart`): environment, dispatcher, audit log, registry, plan executor.
- Settings (`AppSettings`) are user preferences stored separately in SharedPreferences; they never contain financial data.
- go_router with a `StatefulShellRoute` for the bottom-navigation branches (Home, Activity = transactions, Budgets, Goals, More). Forms open as sheets on the root navigator but keep URLs, so they are deep-linkable. Route builders live in `AppRoutes` (`lib/app/router/routes.dart`).

## Persistence (mock backend)

`LocalDataStore` owns one `EntityCollection<T>` per entity and a `ValueStore<T>` for single values (profile, emergency plan, alert inbox). Collections keep items in memory, emit on every change, and persist JSON through a `PersistenceDriver` (`SharedPreferencesDriver` in the app, `MemoryDriver` in tests) with debounced writes. `MockBehavior` can add latency or fail reads/writes to exercise loading and error states. Seed scenarios (`demo`, `empty`, `stressed`) are applied on first launch only.

## Testing

- Domain calculators are pure and take `today` explicitly; `test/domain/fixtures.dart` builds snapshots by hand.
- Actions are tested end-to-end through the dispatcher with `test/actions/action_harness.dart` (`MemoryDriver`, `FixedClock` at 10 Oct 2026 09:00, `SequentialIdGenerator`).
- Widget tests use `test/helpers/test_app.dart` (demo seed, fixed clock, reduced motion).
