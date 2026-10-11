# Brief for feature developers (read fully before coding)

FiNN = premium, privacy-first personal finance Flutter app for Indian users (₹, Indian grouping). Frontend only; data comes from local mock repositories behind interfaces. Quality bar: production fintech.

## Environment
- Flutter SDK NOT on PATH: `C:\Users\Hasrhil\Downloads\flutter\bin\flutter.bat` (3.47.7, Dart 3.13.5, Material 3). Riverpod 3.4.3 (no codegen), go_router 18, fl_chart 1.2, lucide_icons_flutter (`LucideIcons.x` — verify names by grepping `C:/Users/Hasrhil/AppData/Local/Pub/Cache/hosted/pub.dev/lucide_icons_flutter-3.1.24/lib/lucide_icons.dart`; many renamed e.g. `house`, `chartPie`, `circleCheck`, `triangleAlert`). Do not add packages.
- Visual reference: `design.md` (React/shadcn spec of an earlier FiNN). Read only the sections listed in your task. Adapt to our tokens: midnight navy primary, emerald = positive, sunset orange = attention, rose = outflow/critical. Restrained gradients only on hero cards.

## Read first
- `docs/DESIGN_SYSTEM_API.md` — all UI components. Import `package:finn/design_system/design_system.dart`. Use `context.colors`, `context.text`, `context.motion`. Never hard-code colours (white on gradients is OK).
- `lib/app/di/data_providers.dart` — read-side providers (all `AsyncValue`, derived from one `FinanceSnapshot` → always consistent). `lib/app/di/core_providers.dart` (settingsProvider, todayProvider, financeRepositoriesProvider).
- Domain models/calculators in `lib/features/<f>/domain/`, `lib/finance/` (ledger: cash / earmarked / available).
- `lib/app/router/routes.dart` — `AppRoutes` (use `context.push(AppRoutes.x)` / `context.go`). Screen and sheet classes already exist as stubs at the paths the router imports; REPLACE their contents but KEEP the class names and constructor parameters.
- `lib/shared/presentation/`: `action_runner.dart` (`runAction(...)`, `newIdempotencyKey()`), `async_view.dart` (`AsyncView`), `category_icons.dart` (`CategoryIcons.of(key)`, `CategoryAvatar`), `transaction_row.dart` (`TransactionRow`).

## Writes (mandatory pattern)
All mutations go through typed actions → `runAction(context, ref, action: const XAction(), input: XInput(...), idempotencyKey: _key, onFieldErrors: ...)`. It handles confirmation review sheets for consequential actions, toasts, duplicate-submit protection. Keep one `_key = newIdempotencyKey()` per form session (state field); after success pop the sheet. Existing actions: `lib/features/{transactions,pending,loans,goals}/application/*_actions.dart`. If your module needs new actions, create `lib/features/<f>/application/<f>_actions.dart` modelled on `transaction_actions.dart` (descriptor + input with toJson/fromJson via `In`/`Out` helpers + prepare(validate, preview) + execute via `env.repos`). Do NOT edit `lib/app/di/action_catalog.dart`; list your new action classes in your final report. No financial logic in widgets — put calculations in domain/application files.

## UI rules
- Screens: `Scaffold` + `CustomScrollView`/`ListView.builder` (lazy, `PageStorageKey` for scroll restore, `ValueKey(id)` per row). Page padding `Space.gutter`; bottom padding `Space.bottomClearance` on tab roots (nav bar + FAB). Wrap content in `ResponsiveCenter` for tablets. Pull-to-refresh not needed.
- Headers: large title (`context.text.pageTitle`) + optional actions; detail pages use AppBar/back.
- Watch the narrowest provider; use `.select` where possible. No heavy work in build; precompute in providers/domain.
- Loading: skeletons sized like content; errors: `AsyncView`/`ErrorState` with retry; empty: `EmptyState` with action.
- Sheets: build with `FinnSheetScaffold(title, description, footer: primary button, child: form)`; keyboard-safe; validate inline (field errors from `onFieldErrors`); disable submit while running; amounts via `AmountField`; dates via `DateField` (no future dates for completed money movements).
- Distinguish actual vs projected vs pending vs earmarked money in copy and visuals. Never rely on colour alone (sign, icon, label). Semantics labels on custom tappables; touch targets ≥ 48.
- Motion: `StaggeredEntrance` for first-load sections, `AnimatedAmount` for changing hero figures, progress bars animate; all respect reduced motion via `context.motion`.
- Respect `settingsProvider` (hideBalances handled by AmountText automatically; haptics flag).
- Copy: calm, non-judgemental, Indian context.

## Tests
- Harness: `test/helpers/test_app.dart` (`TestEnv.create()`, `env.pumpWidget(tester, widget)`, `env.pumpApp(tester)`, today = 10 Oct 2026, demo seed data). Write widget tests in `test/features/<f>/`. Use `tester.pumpAndSettle()` carefully (skeleton pulse animations are disabled with reduced motion in the harness).

## Finish
Run `flutter.bat analyze <your paths>` and your tests; fix every error/warning/info in your files. Ignore failures in files you do not own. Only edit files inside your assigned folders (+ your tests). Final report ≤ 40 lines: files, new action classes (for registration), known gaps.
