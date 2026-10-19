# FiNN — Google Play release

Package: `app.finn.money` (permanent). Version comes from `pubspec.yaml` (`version: 1.0.0+1` → versionName 1.0.0, versionCode 1). Bump the `+N` build number for every upload.

## 1. Build

```sh
flutter clean
flutter pub get
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

- Upload `build/app/outputs/bundle/release/app-release.aab` (Play only accepts bundles; it generates per-device APKs).
- Keep `build/symbols/` for each release. It is needed to read obfuscated Dart stack traces:
  `flutter symbolize -i <stack.txt> -d build/symbols/app.android-arm64.symbols`.
- Native symbol tables are already inside the bundle (`debugSymbolLevel = SYMBOL_TABLE`). The R8 mapping file is uploaded with the bundle automatically.
- Optional local check of the per-device download size:
  `bundletool build-apks --bundle=app-release.aab --output=finn.apks --connected-device` then `bundletool get-size total --apks=finn.apks`.

## 2. Signing

- Upload key: `C:/Users/Hasrhil/keys/finn-upload.jks`, alias `upload`. The passwords are in `android/key.properties` (git-ignored).
- **Back up the .jks and key.properties somewhere safe and offline (password manager + second drive).** Never commit them.
- In Play Console, accept **Play App Signing**. Google holds the real app-signing key. If the upload key is lost, it can be reset through Play support.
- Without `android/key.properties`, release builds fall back to debug keys. Play rejects those builds.

## 3. What the build already does

- Targets API 36 (Play requirement for new apps since 31 Aug 2026), with minSdk 24.
- R8 code shrinking and resource shrinking; Dart obfuscation; icon-font tree shaking (Flutter default).
- Locale filter `en`: AndroidX translations are stripped because the UI is English-only.
- Permissions: `INTERNET` and `RECORD_AUDIO`. The microphone is requested at runtime only when voice input starts. `android.hardware.microphone` is marked `required="false"`, so devices without a mic can still install the app.
- Backups are off (`allowBackup=false` plus data-extraction rules): no copying of session tokens or the finance cache to the cloud or to a new device.
- Cleartext HTTP is disabled. `debugPrint` is a no-op in release, so nothing financial reaches logcat.
- Splash screens use the app's paper colour, light and dark.

## 4. Play Console checklist

**Store listing**
- App name: FiNN. Short description: 80 characters max. Full description: 4000 characters max.
- App icon: `store/play_store/icon_512.png` (512×512, 32-bit PNG).
- Feature graphic: `store/play_store/feature_graphic_1024x500.png`.
- Phone screenshots: at least 2 are required, and 4–8 is better. They must be 16:9 or 9:16 with sides between 320 and 3840 px. Take them from a release build with realistic demo data.
- Category: Finance. Contact email: finn.team007@gmail.com.

**App content**
- Privacy policy: `https://finn-backend.vercel.app/privacy`
- Account deletion URL: `https://finn-backend.vercel.app/delete-account`. Deletion is also available in the app: Profile → Security → Delete account.
- Ads: No.
- App access: sign-in is required, using an emailed one-time code. **Reviewers need a working login.** Provide a demo account they can enter without access to your inbox (see "Open items").
- Target audience: 18+. Content rating: complete the IARC questionnaire (no violence or gambling; the app handles financial info).
- Financial features declaration: personal finance management (budgeting, expense tracking, savings goals, loan/EMI tracking). The app does **not** offer loans, payments, banking, crypto or trading.
- Government app: No. News app: No. Health: No.

**Data safety form (answers that match the current code)**

| Data type | Collected | Shared | Purpose | Optional? |
|---|---|---|---|---|
| Email address | Yes | No | Account management | Required |
| Other financial info (transactions, budgets, goals, loans, balances) | Yes | No* | App functionality | Required |
| Other user-generated content (assistant requests) | Yes | No* | App functionality | Optional |
| User IDs (FiNN ID) | Yes | No | App functionality, account management | Required |

\* OpenAI (assistant) processes this data on FiNN's behalf as **service providers**. Under Play's rules, that does not count as "sharing".

- Encrypted in transit: Yes (HTTPS only).
- Users can request deletion: Yes (in the app and at the URL above).
- No ads, no analytics, no tracking SDKs, no location, no contacts.

**Testing track**
- Personal developer accounts created after 13 Nov 2023 must run a **closed test with at least 12 testers opted in for 14 consecutive days** before production unlocks. Organization accounts are exempt.
- Recommended order: internal testing (instant, up to 100 testers) → closed testing (12+ testers, 14 days) → production. Use a staged rollout (for example, 20%).
- Check the **pre-launch report** in Play Console for crashes and accessibility issues on real devices.

## 5. Open items before production

1. **Reviewer login:** sign-in uses emailed codes, and reviewers can't read your inbox. Add a review-only account on the backend (a fixed email and code set by env vars, limited to one account) and enter it under App access.
2. Deploy finn-backend so `/privacy` and `/delete-account` are live before submitting.
3. iOS still uses `com.example.finn` (not part of this Android release).
