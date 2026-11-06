# Performance, security and agent-latency hardening (Nov 2026)

Branch `hardening/perf-security` (app) and `security/next-16.4.5` (finn-backend). Rule: no change to what the user sees or what the app does; anything that would change behavior waits for a decision (see "Decisions needed").

## Architecture (as found)

- Flutter 3.47.7 / Dart 3.13.5, Riverpod 3 (no codegen), go_router `StatefulShellRoute`. One immutable `FinanceSnapshot` feeds every projection; every write goes through `OperationDispatcher` (preview → fingerprint confirmation → idempotency → policy → audit).
- Remote mode (default): `ApiClient` (one shared `http.Client`) → `https://finn-backend.vercel.app/api/v1` (Next.js on Vercel, function region `sin1`, edge `bom1` from India) → Supabase Postgres 17 in `ap-southeast-1` (same region as the function).
- `SyncEngine` mirrors the user's records in memory and persists them as JSON in SharedPreferences (offline cache). Freshness: cache shown first, then sync on start, on resume, every 30 s while in the foreground, and after every write (`applyChanges` + `sync`). Server sync (`server/modules/sync/service.ts`) uses a global `sync_seq`, per-user advisory locks (shared items lock both users), repeatable-read reads and never-purged tombstones, so an incremental cursor cannot skip a change. Verified, no change needed.
- Money is int paise end to end; EMI uses BigInt. No floating-point currency.
- Agent: `AgentController` → `AgentRunner` → local intents (no model) or ONE JSON-plan call through `FinnRelayTransport` → `POST /agent/completions` (auth = local JWT check, in-memory rate limit, input rail, `enforceDailyUsage` DB call, OpenAI `gpt-6-luna` `reasoning_effort: none` with moderation in parallel, output rail) → deterministic op compilation on the device → `POST /plans/preview` → user review → `POST /plans/execute` → sync. The model returns a 30-token JSON plan; every word the user reads is written by the app, so token streaming would not show anything earlier.
- Not visible from here: Vercel production env/logs, OpenAI-side queueing. iOS cannot be built or profiled on this Windows machine.

## Research checklist applied (sources: docs.flutter.dev perf pages, OWASP MASVS v2 / MASTG, developer.android.com security pages, OpenAI prompt-caching and production guides)

| Item | Status in FiNN |
|---|---|
| Profile in profile mode, 16 ms frame budget, avoid `saveLayer` | No device available this round; not measured (see Decisions) |
| Heavy work off the UI isolate only where it causes jank (Isolate.run has spawn/copy cost) | Measured: cache decode in `Isolate.run` was slower (30 ms vs 23 ms at 10k rows); kept inline. Removed the repeated re-encode instead |
| Impeller default on Android API 29+ (falls back to OpenGL) | Default, nothing to change |
| R8 + resource shrinking | On (`android/app/build.gradle.kts`) |
| `--obfuscate --split-debug-info` | Already in `store/play_store/RELEASE.md` |
| App size via `--analyze-size` | Pending (needs a release build run) |
| MASVS-STORAGE-1 tokens in keystore/keychain | OK: `flutter_secure_storage`, `first_unlock_this_device` |
| MASVS-STORAGE-1 sensitive data at rest | **Gap**: full financial cache is plaintext JSON in SharedPreferences |
| MASVS-STORAGE-2 no sensitive data in logs/backups | OK: `debugPrint` is silenced in release (`main.dart`), `allowBackup=false` + extraction rules |
| MASVS-NETWORK-1 TLS only | OK: `usesCleartextTraffic=false`, no iOS ATS exceptions |
| MASVS-NETWORK-2 pinning for own endpoints | Not pinned. Android docs advise against pinning without backup pins; Vercel rotates certificates. Decision |
| No secrets in the client | OK: no keys in `lib/`, OpenAI key server-only, `key.properties`/`.env*` not tracked |
| MASVS-PLATFORM screenshots / app switcher (`FLAG_SECURE`, `setRecentsScreenshotEnabled`) | **Gap**: not set. Changes behavior (blocks screenshots) → Decision |
| Biometric / app lock | Not present (feature) → Decision |
| Root/jailbreak awareness | Not present (low value vs false positives for this app) → Decision |
| Dependency audit | Flutter: no advisories reported by pub; 23 locked minor updates. Backend: **critical** `next@16.4.0` (unauthenticated RCE x2 + DoS), **high** `nodemailer@7` |
| Prompt caching: static prefix first, measure cached tokens | Already done: 95 % of input tokens cached |

## Findings (prioritised)

| # | Severity | Where | Finding | Fix |
|---|---|---|---|---|
| 1 | Critical | finn-backend `package.json` | `next@16.4.0`: GHSA unauthenticated RCE (image optimizer SVG, `use cache` typed arrays) + App Router DoS | Bumped to `16.4.5` (patch) on branch `security/next-16.4.5`; needs deploy |
| 2 | High | finn-backend `package.json` | `nodemailer@7`: SSRF/file read via `raw`, header/command injection, DoS (OTP mail path) | Fix is a major upgrade to 10.x → Decision |
| 3 | High | `lib/data/remote/sync_engine.dart` | All financial records stored unencrypted in SharedPreferences (readable on rooted devices, device backups excluded) | Encrypt the cache with a key held in the keystore → Decision (new dependency, one-time migration) |
| 4 | Medium | `MainActivity.kt`, iOS | Balances visible in screenshots/recents | `FLAG_SECURE` or recents-only blur → Decision |
| 5 | Medium (perf) | `sync_engine.dart` `_commit` | Whole cache re-encoded and rewritten after every page and every 30 s poll, even with no changes (3.3 MB / ~13 ms desktop CPU at 10k transactions) | **Fixed** (commit `83b2d71`) |
| 6 | Low (perf) | agent cold path | First agent request after idle: Vercel cold start ~1.0 s + new TLS 110–170 ms | Warm-up on opening the agent → Decision |
| 7 | Info | agent | No per-stage timing to see where time goes | **Fixed**: `AgentTrace` (commit `ce1b739`) |

## Agent: baseline (live, 2026-11-06, demo data, prompt `2026-11-06.1`, `gpt-6-luna`)

`docs/agent-benchmarks/golden_eval_baseline.json` (71 cases, 75 turns, 65 model calls, $0.0037).

Accuracy: normal 100 %, edge 93 % (14/15; `ambiguous_then_choice` saved 0 of 1), Hinglish 100 %, adversarial 100 %.

| Stage (ms) | p50 | p90 | max |
|---|---|---|---|
| snapshot | 0.2 | 0.3 | 1.8 |
| local intents | 0.1 | 0.1 | 1.9 |
| prompt build | 0.0 | 0.1 | 1.2 |
| **model call** (network + model) | **1425** | **1943** | 2728 |
| parse | 0.1 | 0.2 | 2.2 |
| compile | 0.2 | 1.4 | 5.0 |
| preview (local dispatcher) | 5.6 | 8.6 | 14 |
| execute (local dispatcher) | 5.5 | 7.7 | 13 |
| whole turn (agent time) | 1400 | 1867 | 2736 |
| until review card | 1495 | 2194 | 2733 |

Tokens per call (median): 2,446 input of which 2,316 cached, 33 output. One model call per turn; no redundant calls; no tool loop.

Production adds (measured from India with curl): new connection DNS+TCP+TLS 110–170 ms (reused: 0), relay round trip 120–160 ms warm, ~1.0 s cold start on the first request after idle; preview and execute are one round trip each (~150–300 ms) and run only when the turn proposes changes.

Conclusion: >95 % of agent time is the OpenAI call itself. Prompt size, parsing, data loading and the UI are not the bottleneck. Output is 33 tokens, so streaming or trimming output cannot help.

## Decisions (user, 2026-11-06) — next work, in this order

1. **Encrypt the offline cache: YES.** Add `cryptography` (AES-GCM 256). Random key generated once, stored in `flutter_secure_storage` (same options as `SecureSessionStore`, own key name). `SyncEngine._persist` stores `{"v":2,"n":nonce,"c":ciphertext,"m":mac}` (base64); `open` decrypts. Migration: a plaintext cache (old format, starts with `{"cursor"`) is read once and re-saved encrypted. If the key is missing/unreadable or decryption fails: discard the cache (it is re-downloaded by the next sync), never crash. Sign-out (`close`) also deletes the key. Keep encode/decrypt cost in mind (measure at 10k rows; if > ~16 ms move encrypt+encode into `Isolate.run`). Tests: round trip, migration from plaintext, wrong/missing key → empty + resync, other user's cache never readable, sign-out removes key.
2. **App-switcher privacy only (screenshots stay allowed).** Android: `MainActivity` → `setRecentsScreenshotEnabled(false)` on API 33+ (below 33 there is no equivalent without FLAG_SECURE; leave as is). iOS: cover the window with a blur/brand view in `sceneWillResignActive` / `applicationWillResignActive`, remove on active (AppDelegate/SceneDelegate). No Dart change.
3. **Agent warm-up on open: YES** (only this speed-up). When agent mode opens (`agentModeProvider` true, remote mode, consent given), fire one `OPTIONS /api/v1/agent/completions` through the shared `http.Client` (no auth, no body), at most once per ~60 s, errors ignored. Verify the route's `preflight()` runs in the same function as POST. Measure: cold first-request time before/after with curl, and rerun the 71-case live eval (`FINN_LIVE=1 FINN_GOLDEN_REPORT=golden_eval_after flutter test test/agent/live/golden_eval_test.dart`) to confirm accuracy ≥ baseline.
4. **nodemailer 7 → 10: YES** on finn-backend branch `security/next-16.4.5`; fix API changes in `server/mail/`, run `npx vitest run` (460 tests). Do not deploy.

Not chosen: local spending answers, OpenAI priority tier, Vercel always-warm, screenshot blocking.

Then: `flutter build apk --release --analyze-size` (size baseline/after), full `flutter test`, final prose report.
