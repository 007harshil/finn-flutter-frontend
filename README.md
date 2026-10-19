# FiNN

Privacy-first personal finance for Indian users: income and spending, budgets, savings goals, an emergency fund, loans and EMIs, subscriptions, money owed to and by friends, net worth, alerts and a monthly "financial story".

This repository is the Flutter frontend. All data comes from local mock repositories behind interfaces, so a real backend can be connected without touching features (see [docs/BACKEND_INTEGRATION.md](docs/BACKEND_INTEGRATION.md)).

## Highlights

- **Exact money.** Every amount is an integer number of paise (`Money`). Floating point is never used for authoritative values. Display uses Indian digit grouping (₹1,25,000).
- **One consistent view.** All screens derive from a single immutable `FinanceSnapshot`, so balances, budgets, alerts and analytics always agree.
- **Clear money states.** Cash, earmarked (goals and emergency fund) and available-to-spend are separate. Pending obligations and projected charges are never mixed into actual spending.
- **Agent-ready writes.** Every mutation is a typed, serialisable action with validation, a human-readable preview, confirmation for consequential operations, idempotency, a channel policy and an audit log.

## Requirements

- Flutter 3.47 / Dart 3.13 (see `pubspec.yaml`).
- Packages: flutter_riverpod 3, go_router 18, fl_chart, intl, shared_preferences, lucide_icons_flutter, pdf, share_plus, path_provider.

## Run

```sh
flutter pub get
flutter run                                         # demo data, 250 ms simulated latency
flutter run --dart-define=FINN_SCENARIO=empty       # brand-new user
flutter run --dart-define=FINN_SCENARIO=stressed    # overdue items, breached budgets, zero-income month
flutter run --dart-define=FINN_LATENCY_MS=0         # no simulated latency
```

The scenario is only seeded on first launch; data then persists locally (SharedPreferences, JSON).

## Test and analyze

```sh
flutter analyze
flutter test                      # everything
flutter test test/domain          # calculators, ledger, snapshot, alerts, analytics, timeline
flutter test test/actions         # dispatcher, plans and every action module
```

- `test/domain/` — pure unit tests; `fixtures.dart` builds records and snapshots explicitly.
- `test/actions/` — actions run through the real `OperationDispatcher` against an in-memory store (`action_harness.dart`, today = 10 Oct 2026).
- `test/features/`, `test/design_system/` — widget tests using `test/helpers/test_app.dart`.

## Project layout

```
lib/
  core/            money, dates, ids, clock, Result/AppFailure, persistence primitives
  domain/          repository contracts + FinanceRepositories bundle
  data/            local mock repositories, DTOs (JSON codecs), seed scenarios
  finance/         ledger (cash / earmarked / available) and FinanceSnapshot
  actions/         action framework: FinancialAction, dispatcher, policy, audit, registry, plans
  features/<f>/    domain (models + calculators), application (actions, providers), presentation (screens)
  design_system/   tokens, theme, motion, components
  app/             DI providers, router, shell
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layers, data flow, state management, actions.
- [docs/FINANCIAL_MODEL.md](docs/FINANCIAL_MODEL.md) — money, rounding, ledger semantics and the rules behind every figure.
- [docs/BACKEND_INTEGRATION.md](docs/BACKEND_INTEGRATION.md) — replacing the mock repositories with a real API.
- [docs/DESIGN_SYSTEM_API.md](docs/DESIGN_SYSTEM_API.md) — UI components.

## Privacy

FiNN has no ads, analytics or tracking SDKs. Release builds sign in with an emailed code and sync to the FiNN API (https://finn-backend.vercel.app); the device keeps an offline cache that is excluded from Android backups. The assistant sends requests to OpenAI via the FiNN API. Voice input uses the device's own speech recognition; audio never reaches FiNN servers. Users can export data (CSV, JSON or PDF, from Settings → Export) and delete their account in the app. Balances can be masked app-wide. Policy: https://finn-backend.vercel.app/privacy.

## Release

See [store/play_store/RELEASE.md](store/play_store/RELEASE.md) for the Play Store build, signing and console checklist.
