# FiNN build — progress / handoff

Resume in a new chat with: "Continue the FiNN build. Read docs/PROGRESS.md first."

Flutter SDK (not on PATH): `C:\Users\Hasrhil\Downloads\flutter\bin\flutter.bat` (3.47.7 / Dart 3.13.5).
Original spec = the long FiNN prompt (production Flutter fintech app, frontend only, mock data, agent-ready actions). Visual reference: `design.md`.
User prefs: command-line-only subagents → model `haiku`, effort `low`. Stop and hand off when context gets large.

## Architecture decisions (done)
- State: flutter_riverpod 3.4.3 (no codegen). Routing: go_router 18 (StatefulShellRoute). Charts: fl_chart 1.2. Icons: lucide_icons_flutter (`LucideIcons`).
- Money: `lib/core/money/money.dart` int paise; `money_format.dart` Indian grouping. Dates: `lib/core/time/`.
- Domain models per feature: `lib/features/<f>/domain/`. `TransactionCategory` (renamed from Category — clashes with Flutter).
- Repos: contracts `lib/domain/repositories.dart`, bundle `lib/domain/finance_repositories.dart`; local mock impl `lib/data/local/local_data_store.dart` (EntityCollection, JSON persisted via SharedPreferences); seed `lib/data/mock/seed_data.dart` (scenarios demo/empty/stressed); DTOs `lib/data/dto/dtos.dart`.
- Consistency: `lib/finance/finance_snapshot.dart` — one immutable snapshot, all projections lazy/memoised from it. Ledger: `lib/finance/ledger.dart` (cash, earmarked, available).
- Calculators: loans (`loan_calculator.dart`, exact BigInt EMI, rounded up to rupee), budgets, goals, emergency fund, net worth, alerts (`alert_engine.dart`), analytics, timeline.
- Actions (agent-ready): `lib/actions/` (action.dart, dispatcher.dart w/ idempotency+confirmation fingerprints+policy+audit, action_registry.dart, action_plan.dart). Implemented: transactions, pending, loans, goals (`lib/features/*/application/*_actions.dart`).

## Phase 2 (parallel agents, spawned 2026-10-10)
Each agent follows `docs/AGENT_BRIEF.md`. Groups: A tests+docs, B home/alerts/timeline/more/onboarding, C transactions+categories, D budgets+goals+emergency fund, E loans+subscriptions+pending, F analytics+net worth+settings+export.
After all finish: register new actions in `lib/app/di/action_catalog.dart`, full `flutter analyze` + `flutter test`, journey tests (`test/journeys/` + `integration_test/`), final review.
If an agent's work is missing when resuming: check `git`-less state by looking whether stub text `Placeholder — replaced by the feature implementation.` still exists in the screen files (`grep -rl "Placeholder — replaced" lib`).

## Phase 2 resume (2026-10-11) — agents hit usage limit; respawned for leftovers
- Done: B (home/alerts/timeline/more/onboarding), C (transactions+categories), budgets, goals, pending, analytics, all `*_actions.dart`, export service/controller, domain tests (money/time/budget/goal+EF/loan), subscription + pending action tests.
- D2 done (7 widget tests). To register in catalog: `ConfigureEmergencyFundAction`, `EmergencyFundMovementAction.contribute()`, `.withdraw()`. Fixed missing data_providers import in analytics_screen.dart.
- E2 done (loans + subscriptions UI, 20 tests; new `loan_ui.dart`, `application/loan_quote.dart`). No new actions. Follow-up: `FinnTextField` with `suffix` + text triggers semantics assertion `node.isMergedIntoParent` — fix in design system.
- F2 done (net worth/settings/export UI, 15 tests; helpers `net_worth_view.dart`, `data_reset.dart`, `settings_widgets.dart`).
- Main session: registered all 39 actions in `action_catalog.dart`; fixed FinnTextField suffix semantics assertion (`_labelled` in inputs.dart no longer uses MergeSemantics; test `test/design_system/text_field_suffix_test.dart`).
- A2 done (≈200 new domain/action tests; README, ARCHITECTURE, FINANCIAL_MODEL, BACKEND_INTEGRATION). Fixed its 2 category copy bugs + stale comment in repositories.dart.
- Checkpoint 2026-10-11: `flutter analyze` clean, `flutter test` 354 passed / 0 skipped.
- Journeys done: 8 in `test/journeys/` + `integration_test/app_journey_test.dart` (smoke, not yet run on device). Fixed reduced-motion AnimatedSize crash → shared `MotionAnimatedSize` (layout.dart), used in onboarding + analytics HowCalculated.
- Checkpoint: analyze clean, 364 tests pass.
- NEXT: final review (code-review pass), run integration_test on a device/desktop.
- 2026-10-11 Home: removed NET + savings-rate cards from Cash flow. "What needs attention" is now a horizontal PageView carousel (peek of next card, count badge + severity breakdown in header, dots, "+N more" end card). AlertCard redesigned picture-first: `FinancialAlert.visual` (sealed `AlertVisual` in alert.dart, filled by AlertEngine) drives CustomPainter illustrations in `alerts/presentation/alert_visuals.dart` (calendar, gauge, shield, ring+confetti, plan line, scale). Added flutter_animate. Animations are finite (pumpAndSettle-safe) and off under reduced motion. `savingsHealthProvider` now unused on Home. 377 tests pass.
- 2026-10-11 Home: "Coming up" is 7 days (`UpcomingWindow.days`), EMIs + subscriptions only (pending removed: pending items are never late). Provider now yields `UpcomingOverview` with `toArrange` ("Keep ready" total) + `expectedIn`. List scrolls inside a max-height card (4.5 rows); nested list uses restorationId `nested_upcoming_list`, which `journey_helpers` skips. `PendingOverview.overdueCount` replaced by `longPending` (open > 21 days, oldest first), shown as an info note in the home Pending section with day counts. Visible `_SectionDivider` (24 dp each side) between home sections. 379 tests pass.
- 2026-10-11 Home: module summaries (Loans, Goals, Emergency fund, Pending, "Your month so far", "Recent moments") replaced by `QuickAccessGrid` (`home/presentation/widgets/quick_access_grid.dart`): bento of 5 unequal tiles (tall Loans; Pending over Emergency fund; Goals + wide Timeline), name + icon + hint only, tap opens module. Staggered pop-in, icon elastic pop, one shimmer, press squish; all finite and off under reduced motion. Deleted `module_sections.dart` + `story_sections.dart`. Tiles keyed `quick-tile:<title>`; test `test/journeys/home_quick_access_journey_test.dart`. 380 tests pass.
- 2026-10-11 Insights: one topic at a time. Pinned horizontal chips (`InsightsSection` enum + `insightsSectionProvider` in analytics_providers.dart): Overview, Daily spend, In vs out, Categories, Payments, Budgets, Savings, Loans, Subscriptions. Chips keyed `insights-chip:<name>`, overview tiles `insights-explore:<name>`. Sections in `analytics/presentation/sections/` (overview, flow, breakdown, commitment); shared widgets `insight_widgets.dart` (GrowIn, TakeawayCard, KpiStrip, RingGauge, SplitBar, RelativeBar w/ marker, SparkBars). Charts grow in once (GrowIn) + dashed average lines; new DailySpendChart, MonthlySpendChart, WeekdayChart, tappable CategoryDonut. `InsightsData` gained dailySpend, weekdayAverages, topExpenses, goals, loans + baseline getters (avg monthly income/expense/net, projected month spend, budget pace/safe daily, debt-free months). Test `test/journeys/insights_chips_journey_test.dart`. 383 tests pass.
- 2026-10-11 Home top: hero + cash flow merged into one block (`_MoneyAtAGlance` in home_screen.dart, no divider). Hero (`hero_balance_card.dart`): count-up amount, "N% of cash" chip (warning "Over-committed" when set-aside > cash), CustomPainter cash bar (bright = free, hatched = set aside; sweep-in + one shine), tap bar toggles split into goals / emergency fund. Cash flow (`period_overview.dart`): single card, compact month label in header (slides by direction, "so far" for current month), horizontal swipe changes month, savings-rate ring + Income/Spent bars on one scale + "Kept"/"Overspent by" line, spend delta vs same days of last month (`rangeSummaryProvider`). All animations finite, off under reduced motion. Test `test/journeys/home_money_glance_journey_test.dart`. 384 tests pass.
- (history) Respawned: A2 remaining tests (ledger/net worth/alerts/analytics/action modules) + docs (README, ARCHITECTURE, FINANCIAL_MODEL, BACKEND_INTEGRATION); D2 emergency fund UI; E2 loans UI + subscriptions UI; F2 net worth UI + settings UI + export screen.

## Status
- [x] core, tokens/theme/motion, domain, persistence, seed, calculators, action framework + 4 modules
- [x] router (`lib/app/router/`), shell (`lib/app/shell/app_shell.dart`), app.dart, main.dart, DI (`lib/app/di/`), shared presentation (`lib/shared/presentation/`), test harness (`test/helpers/test_app.dart`), platform deep links
- [x] design-system components (agent) → `lib/design_system/components/`, barrel `lib/design_system/design_system.dart`
- [ ] DI providers `lib/app/di/`
- [ ] remaining actions: categories, budgets, subscriptions, emergency fund, assets, profile + catalog
- [ ] router/shell, feature UIs (home, transactions, budgets, goals+EF, loans, subscriptions, pending, analytics/net worth, alerts, timeline, settings/export/onboarding)
- [ ] tests (unit/widget/journeys), docs (README, ARCHITECTURE, FINANCIAL_MODEL, BACKEND_INTEGRATION), analyze clean
