# Money accounts (replaces payment methods)

Status: approved 2026-10-15. Replaces the fixed `PaymentMethod` enum
(UPI / Card / Cash / Bank Transfer / Wallet / Other) with **money accounts**
the user creates for themselves: cash, bank accounts and cards, each with its
own balance. Every money movement says which account it hit.

User decisions (2026-10-15):
- Credit cards are tracked as **amount owed**, never added to total money.
- Existing data moves into one **Cash** account per user (old opening balance +
  every old transaction), so totals do not change.
- **Transfers** between own accounts are supported (ATM withdrawal, credit-card
  bill payment). Transfers are not income or spending.
- Optional **channel** (sub-type) per movement: suggestions + free text.

## 1. Account model

| field | type | rules |
|---|---|---|
| `id` | text | client generated (`acc_…`); migrated / bootstrapped cash account is `acc_cash` |
| `name` | text | 1–40 chars, trimmed. e.g. "SBI", "Axis", "Cash", "HDFC Millennia" |
| `kind` | enum | `cash`, `bank`, `debitCard`, `creditCard`, `promoCard`, `otherCard` |
| `institution` | text? | ≤40, bank / issuer name ("SBI"); optional |
| `last4` | text? | exactly 4 digits; cards only (null for cash/bank) |
| `openingPaise` | int | ≥ 0. Asset kinds: money in it on `openingDate`. `creditCard`: amount owed on `openingDate` |
| `openingDate` | date | balance is "as of" this date; movements dated before it are ignored for this account |
| `creditLimitPaise` | int? | > 0, `creditCard` only, optional |
| `isDefault` | bool | exactly one non-archived default per user; preselected in forms; used when an input omits `accountId` |
| `isArchived` | bool | hidden from pickers and Home; history and balance kept; cannot be default |
| `sortOrder` | int | display order (ascending, then createdAt) |
| `note` | text? | ≤ 200 |
| `version`, `createdAt`, `updatedAt` | | usual optimistic-concurrency fields |

Kind labels: Cash, Bank account, Debit card, Credit card, Promo / gift card, Other card.
`isLiability = kind == creditCard`. All other kinds are **asset accounts**.

Every user always has at least one non-archived account. Bootstrap (new user)
creates `acc_cash` "Cash", kind `cash`, opening 0, openingDate = today,
`isDefault = true`. Onboarding's opening balance sets the Cash account's
`openingPaise`/`openingDate` (profile `openingBalance` keeps being written for
compatibility but the ledger no longer reads it).

## 2. Balance formula

For account `a`, counting only movements dated `a.openingDate ≤ date ≤ today`:

```
flow(a) = Σ income txns on a − Σ expense txns on a + Σ transfers into a − Σ transfers out of a

asset account balance  = a.opening + flow(a)          (can go negative = overdrawn)
credit card owed       = a.opening − flow(a)          (spend raises owed; payment/refund lowers)
credit card limit left = creditLimit − owed           (only if creditLimit set)

cash (total money)     = Σ balance of asset accounts (archived included)
creditOwed             = Σ owed of credit cards (archived included)
earmarked / available  = unchanged (available = cash − earmarked)
net worth              = existing formula − creditOwed (credit-card debt is a liability)
```

Example: SBI debit 10,000 + Axis bank 4,000 → cash 14,000. Buy toy ₹1,000 on
SBI debit → SBI 9,000, cash 13,000.

Profile `openingDate` stays the **tracking start** for analytics. The existing
auto-extend rule applies per account as well: writing a transaction or transfer
dated before an account's `openingDate` moves that account's `openingDate`
back to the movement date (and the profile's, as today).

Analytics (income/spend/budgets/categories) still use all income/expense
transactions regardless of account — a credit-card purchase is spending.
Transfers never appear in income, spending or budgets. Loan disbursement rule
unchanged.

## 3. Transactions and other movements

`transactions` gains:
- `accountId` text, **required** (DB NOT NULL after backfill). Input may omit
  it → server/app resolves to the user's default account.
- `channel` text?, ≤ 30 chars, trimmed, empty → null. Free text. App suggests:
  `UPI`, `IMPS`, `NEFT`, `RTGS`, `Net banking`, `Cheque`, `Tap / swipe`, `ATM`.
- `paymentMethod` is **removed** from the wire format and inputs. The DB column
  stays (legacy, no longer written); no DROP.

Same `accountId` (+ optional `channel`) replaces `method` / `paymentMethod` on:
- `subscriptions.accountId` (optional: "charged to"). Mark-paid input takes
  `accountId?` (falls back to subscription's account, then default).
- `pendingSettlements.accountId` (+`channel`): the account the settlement money
  moved through; copied onto the linked transaction.
- loan repayment / disbursement inputs: `accountId?` (+`channel?`) → copied onto
  the linked transaction (replaces `method`; disbursement used to hardcode
  `bankTransfer`, now default account unless given).

Validation: referenced account must exist, belong to the user and not be
archived (for new writes; editing an old txn on an archived account keeps it).

## 4. Transfers

New entity `Transfer`: `id` (`trf_…`), `fromAccountId`, `toAccountId`
(different, both the user's, not archived for new writes), `amountPaise` > 0,
`date` (not in future), `channel?` (≤30), `note?` (≤500), `version`,
`createdAt`, `updatedAt`. Examples: SBI → Cash (ATM), SBI → HDFC credit card
(bill payment).

## 5. Actions (same ids both sides)

| id | input | notes |
|---|---|---|
| `accounts.create` | `name, kind, institution?, last4?, openingBalance(money), openingDate?(default today), creditLimit?(money), isDefault?, note?` | duplicate name+kind → warning |
| `accounts.update` | `id, version?, name, kind, institution?, last4?, openingBalance, openingDate, creditLimit?, note?` | kind change asset↔creditCard allowed only if account has no movements |
| `accounts.setBalance` | `id, balance(money), asOf?(default today)` | "Correct balance": sets `openingPaise` so the computed balance (owed for credit) on today equals `balance`; preview shows old → new |
| `accounts.setDefault` | `id` | unsets previous default |
| `accounts.archive` | `id, archived(bool)` | cannot archive the last active account or the default (choose another default first) |
| `accounts.delete` | `id` | only when no transactions, transfers, subscriptions, settlements reference it; otherwise validation error suggesting archive; cannot delete last account |
| `transfers.create` | `fromAccountId, toAccountId, amount, date, channel?, note?` | |
| `transfers.update` | `id, version?, …same` | |
| `transfers.delete` | `id` | |
| `transactions.create/update` | existing fields − `paymentMethod` + `accountId?`, `channel?` | |

Field names in action inputs follow existing conventions (money fields like
`amount`/`openingBalance` use the same encoding the existing actions use —
check `In.money` / backend `zMoney`).

## 6. Wire / sync

New sync collections: `moneyAccounts`, `transfers` (same mechanics as `assets`).

`MoneyAccountDto`:
```json
{ "id": "acc_cash", "name": "Cash", "kind": "cash", "institution": null, "last4": null,
  "openingPaise": 250000, "openingDate": "2026-09-01", "creditLimitPaise": null,
  "isDefault": true, "isArchived": false, "sortOrder": 0, "note": null,
  "createdAt": "…", "updatedAt": "…", "version": 1 }
```
`TransferDto`:
```json
{ "id": "trf_1", "fromAccountId": "acc_sbi", "toAccountId": "acc_cash", "amountPaise": 200000,
  "date": "2026-10-10", "channel": "ATM", "note": null, "createdAt": "…", "updatedAt": "…", "version": 1 }
```
`TransactionDto`: drop `paymentMethod`; add `"accountId": "acc_cash"`, `"channel": null`.
`SubscriptionDto`: drop `paymentMethod`; add `"accountId": null|string`.
`PendingSettlementDto`: drop `method`; add `"accountId"`, `"channel"`.

Balance read model (backend `BalanceSnapshot`, Flutter `BalanceSnapshot`)
adds `cashPaise` (asset total), `creditOwedPaise`, and
`accounts: [{ accountId, balancePaise }]` (balance = owed for credit cards).
Keep existing fields; `openingBalancePaise` = Σ asset-account openings.

Period summary `byMethod` → replaced by `byAccount: [{accountId, amountPaise}]`
(expense per account, desc) and `byChannel: [{channel, amountPaise}]`
(expense with a channel, desc).

Import (`POST /api/v1/import`) accepts `moneyAccounts` and `transfers`; device
data without accounts is migrated with the rules in §7 before upload.

## 7. Data migration

DB (`finn-backend/supabase/migrations/20261015120000_finn_money_accounts.sql`):
1. create `money_accounts`, `transfers` (+RLS/grants mirroring `assets`, sync_seq, indexes, `finn_api` grants like other tables).
2. for every user with categories or profile: insert `acc_cash` "Cash", kind cash,
   `opening_paise = coalesce(profile.opening_paise, 0)`,
   `opening_date = coalesce(profile.opening_date, min(transaction date), current_date)`, default.
3. `transactions.account_id = 'acc_cash'`, `channel` = label of old payment_method
   when it was `upi` (UPI) / `bankTransfer` (Bank transfer) / `card` (Card) / `wallet` (Wallet), else null.
   Same for `pending_settlements`. Subscriptions: `account_id = 'acc_cash'` where payment_method not null.
4. `transactions.account_id` set NOT NULL; FKs `(user_id, account_id) → money_accounts(user_id, id)`.
   No DROP statements (the Supabase connector refuses them).

Device (Flutter local store, mock mode): same rules on load when the stored data
has no `moneyAccounts` key.

## 8. UI

- **Home top**: under the hero total, an "Accounts" strip: one quiet row/tile
  per active account (name, kind/last4, balance; credit cards show "owed" and
  limit left in the out colour), tap → account detail; "Manage" → accounts
  screen. Hero total = cash (asset total); credit owed shown as a secondary
  figure when non-zero.
- **Accounts screen** (drawer + Home "Manage"): asset accounts grouped (Cash,
  Banks, Cards), credit cards separately; add / edit / correct balance / set
  default / archive / delete.
- **Account detail**: balance, movements on this account (transactions + transfers).
- **Transaction form**: account picker (default preselected) replaces payment
  method; optional channel chips (suggestions + custom). Same picker in
  subscription, loan payment, settle-pending sheets.
- **Transfer form**: from, to, amount, date, channel, note. Entry from Home
  accounts strip, accounts screen, and add menu.
- Activity shows transfers as neutral rows; filters by account instead of method.
- All on `lib/kit` "calm ledger" (no gradients/gold/glow).
