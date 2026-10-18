# Savings on an account

Status: 2026-10-18. Builds on [MONEY_ACCOUNTS.md](MONEY_ACCOUNTS.md).

Problem: adding money to a goal or the emergency fund lowered the total
available, but did not say WHICH account the money sits on. The user could not
tell "do not spend this from my SBI account, it is my emergency fund".

## Rules

- Setting money aside (goal contribution, goal starting amount, emergency-fund
  contribution) now happens **on an account** (`accountId`, default account when
  omitted). Only asset accounts (cash, bank, debit/promo/other card) can hold
  savings; a credit card is refused ("A credit card cannot hold savings.").
- Saving is **not spending**: the account's balance does not change. Per account:

  ```
  balance (total)        unchanged by saving
  set aside              Σ contributions − Σ withdrawals on that account
  available to spend     balance − set aside
  ```

  Totals: `cash` = Σ balances; `earmarked` (set aside) = Σ set aside;
  `available` = cash − earmarked (as before).
- A contribution cannot exceed the account's **available to spend**
  ("Only ₹4,000 in HDFC is free to set aside."), even if other accounts have
  money. Spending later can push an account's available below zero (set-aside
  money is never touched); show it as "over-reserved" in the out colour.
- A **withdrawal** (release) takes `accountId` optionally. With it: only what the
  bucket holds on that account ("Only ₹2,000 is set aside on HDFC."). Without it:
  the server releases from the accounts holding the most first (one movement
  per account; the action result is the first). Deleting a goal releases
  everything it holds on every account.
- Old allocations were moved to the Cash account (`acc_cash`) by the migration;
  `accountId` null means "on no account" (only possible for imported/very old
  rows) and counts in the overall set-aside only (`earmarkedUnassignedPaise`).
- An account that has savings set aside on it cannot be deleted (archive it).

## Wire

`SavingsMovement` DTO (sync collection `savingsMovements`) gains
`"accountId": "acc_sbi" | null`.

Action inputs:

| action | new field |
| --- | --- |
| `goals.create` | `accountId?` for `initialAllocation` |
| `goals.contribute` | `accountId?` |
| `goals.withdraw` | `accountId?` |
| `emergencyFund.contribute` | `accountId?` |
| `emergencyFund.withdraw` | `accountId?` |

Preview lines now include "Set aside on", "Free to spend in <account>" and
"Available to spend (total)". Validation errors: `fieldErrors.amount`,
`fieldErrors.accountId` (cards / unknown account).

Balance read model `accounts[]` entries gain `earmarkedPaise` and
`availablePaise`; the snapshot gains `earmarkedUnassignedPaise`.

Import (`POST /import`): `savingsMovements[].accountId` optional (missing → the
payload's default account).

## UI

- Every set-aside form (goal contribute / withdraw / create starting amount,
  emergency fund add / withdraw) gets an **account picker** (default
  preselected for adding; for releasing "Where it is held" with the accounts
  that hold some, each showing the amount held).
- The picker rows for adding show each account's **Free to spend**.
- Home accounts strip and the accounts screen / account detail show per account:
  **Total**, **Set aside** (when > 0) and **Available to spend**. The hero
  shows total money, set aside, and available (as today).
- Goal and emergency fund detail show **where the money is held** (account →
  amount).
