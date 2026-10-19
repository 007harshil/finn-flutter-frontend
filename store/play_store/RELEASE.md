# FiNN — Google Play release

Developer: **Zenvora Labs** (personal Play Console account). Package: `app.finn.money` (permanent).
Version comes from `pubspec.yaml` (`version: 1.0.0+2` → versionName 1.0.0, versionCode 2). Bump `+N` for every upload; Play rejects a versionCode it has seen before.

## 0. Order of work

1. Deploy finn-backend (migration `finn_blocks_reports` is already live) and set the review env vars (section 3).
2. Build the bundle (section 1) and upload to **Internal testing**.
3. Fill in every **App content** form and the store listing (sections 4–6) before creating the closed test.
4. **Closed testing**: 12+ real testers opted in for 14 continuous days, with at least one update during the test.
5. Apply for production, then roll out in stages.

## 1. Build

```sh
flutter clean
flutter pub get
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

- Upload `build/app/outputs/bundle/release/app-release.aab`.
- The app talks to `https://finn-backend.vercel.app` by default (`lib/data/remote/api_config.dart`): every record is stored in the Supabase database, not only on the phone. Never pass `--dart-define=FINN_API_URL=` (empty) for a store build — that is the offline mock.
- Keep `build/symbols/` per release: `flutter symbolize -i <stack.txt> -d build/symbols/app.android-arm64.symbols`.
- 16 KB page sizes: all 64-bit native libraries are 16 KB aligned (checked 2026-10-20). Play Console › App bundle explorer › "Memory page size" should say supported.

## 2. Signing

- Upload key: `C:/Users/Hasrhil/keys/finn-upload.jks`, alias `upload`; passwords in `android/key.properties` (git-ignored).
- **Back up the .jks and key.properties offline (password manager + second drive).** Never commit them.
- Accept **Play App Signing**. If the upload key is lost, Play support can reset it.

## 3. Reviewer login (App access)

Reviewers cannot read emailed codes, and "Need login credentials" is a top rejection reason. The backend has a review sign-in:

- Vercel › finn-backend › Settings › Environment Variables (Production):
  - `REVIEW_EMAIL` = `play-review@zenvoralabs.com` (any valid address; no email is sent to it)
  - `REVIEW_CODE` = a 6-digit code you choose (not 123456)
- Redeploy. For that address the code is always `REVIEW_CODE`, with the normal 5-attempt and rate limits. Account-deletion codes for it are the same code, so reviewers can test deletion.
- On the first sign-in the account is filled with three months of demo data (accounts, transactions, budgets, a goal, subscriptions, a shared item).
- Test it yourself on the release build before submitting.
- Play Console › App content › **App access** › "All or some functionality is restricted" › add instructions:
  - Username: the review email. Password: the review code.
  - Notes: "Sign in: enter the email, tap Continue, then enter the 6-digit code above (no email is sent for this account). On first launch, enter any name and opening balance. The AI assistant is the centre button in the bottom bar."
- Keep the review login on for as long as the app is published: Google re-reviews updates and can re-check anytime.

## 4. Store listing (Main store listing)

- App name (30 max): `FiNN: Budget & Expense Tracker`
- Short description (80 max): `Track spending, budgets, goals and EMIs. Tell the AI assistant, approve, done.`
- Full description (4000 max): see `listing.md`.
- App icon `store/play_store/icon_512.png`, feature graphic `store/play_store/feature_graphic_1024x500.png`.
- Phone screenshots: 4–8, portrait, from the **release build** signed in to the review account (real UI only, no fake features, no device frames with other brands, no "No.1/Best/Free" banners).
- Category: **Finance**. Contact email: finn.team007@gmail.com. Website (optional): leave empty or the privacy page.
- Price: **Free**. Warning: once an app is published as free it can never be changed to paid. In-app purchases or subscriptions can still be added later.

## 5. App content (Policy › App content) — answer every item

| Form | Answer |
|---|---|
| Privacy policy | `https://finn-backend.vercel.app/privacy` (also linked in the app: Login screen and Settings › About & privacy) |
| App access | Restricted; credentials from section 3 |
| Ads | No ads |
| Content rating (IARC) | Category: Utility/Productivity/Other. No violence, sex, drugs, gambling. **Users can interact**: yes (friends can share pending items; block and reject exist). Shares location: no. Digital purchases: no. Answer honestly that the app has an AI assistant if asked. |
| Target audience | **18 and over only**. Not appealing to children. |
| News app | No |
| Data safety | Table below |
| Government app | No |
| Financial features | FiNN offers **no** banking, loans, credit, payments, transfers of real money, investing, trading, crypto or insurance. If the form has a budgeting / personal finance management option, pick only that. Otherwise certify that the app does not provide financial features. Never tick loans: "loan tracking" is a personal ledger, not lending. |
| Health apps | No health features |
| Advertising ID | **No** (no ads/analytics SDKs; the merged manifest has no `AD_ID` permission) |

### Data safety

Collected (all **encrypted in transit: yes**; **users can request deletion: yes**, in app and at `/delete-account`):

| Category › type | Collected | Shared | Purposes | Required? |
|---|---|---|---|---|
| Personal info › Email address | Yes | No | Account management | Required |
| Personal info › Name (display name) | Yes | No | App functionality, Account management | Required |
| Personal info › User IDs (FiNN ID) | Yes | No | App functionality | Required |
| Financial info › Other financial info (transactions, balances, budgets, goals, loans, card last 4 digits) | Yes | No | App functionality | Required |
| App activity › Other user-generated content (assistant requests, AI-reply reports, shared item notes) | Yes | No | App functionality | Optional |

- Not collected: location, contacts, photos, files, audio (voice goes to the phone's own speech recognizer; the app only receives text), device IDs, crash/analytics data, web history.
- "Shared" is **No** because OpenAI (assistant), Supabase, Vercel and Google SMTP act as **service providers**, and items a user shares with a friend are **user-initiated** transfers. Both are Play's exemptions from "sharing".
- Rate limiting reads the IP in memory only (ephemeral) — not declared.
- Re-check this table whenever an SDK or feature changes. A Data safety mismatch is a common cause of removal and strikes.

## 6. Policy items built into the app (2026-10-20)

- **AI-generated content**: flag button on every assistant reply → reason + note → `POST /agent/reports` (table `agent_reports`). Review open reports in Supabase: `select * from agent_reports where status = 'open' order by created_at desc;`
- **User-generated content**: Block on friends and friend requests (`/friends/blocks`), Blocked list with Unblock in Friends. A blocked person cannot find or ask you.
- **Account deletion**: in app (Profile › Security › Delete account) and on the web (`/delete-account`).
- **Truthful disclosures**: removed every "your data stays on this device" claim (data is stored on the server).
- **In-app privacy policy** link on the login screen and in Settings.
- Local-only "Load sample data" / "Erase all data" are hidden in the connected app (they always failed there).

## 7. Closed test and production access (personal accounts)

- 12+ testers opted in for 14 **continuous** days. Use real people (friends, family, colleagues) with Android phones, and ask them to use the app on several days. Do not buy tester-farm services: Google judges engagement and rejects or flags fake testing.
- Ship at least one update during the test (bump `+N`) that fixes feedback.
- The production application asks how you recruited testers, what feedback you got and what you changed. Write real, specific answers.
- After approval: production, staged rollout (20% → 50% → 100%), watch Android vitals and the pre-launch report.

## 8. Things that get apps rejected or accounts suspended — and our status

| Risk | Status |
|---|---|
| Reviewer cannot log in | Fixed (review login, section 3) |
| Privacy policy missing, not in app, or not matching the app | Live page names Zenvora Labs, lists data, providers, retention, deletion, contact; linked in app |
| Data safety mismatch | Table above matches the code |
| No account deletion | In app + web |
| Misleading claims in app or listing | Fixed in app; listing text avoids "best/#1/guaranteed" |
| AI app without in-app reporting | Fixed (flag button) |
| UGC without block/report | Block added; friends-only sharing |
| Broken or placeholder features | Local-only buttons hidden; backend must be up during review |
| Target API too low | targetSdk 36 |
| 16 KB page size | Compliant |
| Impersonation / IP | Own name and icon; demo data uses "Demo Bank" |
| Debuggable / test builds | Release build, R8, obfuscated |
| Repeated rejections, multiple or linked accounts, false identity | Use one account with your real verified identity; fix every rejection fully before resubmitting; never open a second account to get around a rejection |
| Ignored policy emails | Watch finn.team007@gmail.com and the Play Console inbox; act before deadlines |

## 9. Owner tasks outside the code

- Set an OpenAI usage limit (the assistant is paid per request).
- Keep the Vercel and Supabase projects on, and not paused for inactivity.
- iOS still uses `com.example.finn` (not part of this Android release).
