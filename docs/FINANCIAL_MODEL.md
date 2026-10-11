# Financial model

The rules behind every figure FiNN shows. Each rule names the code that implements it; tests in `test/domain/` and `test/actions/` pin the behaviour.

## 1. Money and rounding

- `Money` (`lib/core/money/money.dart`) is an exact integer number of **paise**. `double` is used only for chart rendering (`toDouble()`).
- Amounts on records are always positive; direction is explicit (`TransactionType`, `PendingDirection`, `LoanDirection`, `SavingsMovementKind`).
- User input (`Money.tryParse`) accepts `1,25,000`, `₹ 499.5`, `12000.75`; rejects negatives and more than two decimals.
- Nothing rounds implicitly. Every division names a `RoundingMode` (`halfUp` default, `halfEven`, `down`, `up`) via `roundDiv` / `roundDivBig` / `Money.scale`. Calculations that can overflow 64 bits (EMI growth factors, scaling) use `BigInt`.
- Ratios are integer **basis points** (`ratioBps`, half-up; `null` when the denominator is zero, meaning "unknown", never 0%).
- `allocateEvenly` splits an amount so the parts sum exactly to the whole (remainder paise go to the first parts).
- Display: Indian digit grouping (`money_format.dart`); paise are hidden in lists unless the "show paise" setting is on. Stored values always keep paise.

| Calculation | Rounding |
|---|---|
| Loan periodic interest | half-up to the paisa |
| EMI | exact annuity, rounded **up** to the paisa, then **up** to the whole rupee |
| Zero-rate EMI | principal ÷ n rounded up, then up to the rupee |
| Goal "required per month" | up to the paisa (never under-states) |
| Goal / analytics averages | half-up |
| Months to finish a goal | up (a partial month counts) |
| Emergency coverage (tenths of a month) | down (never over-states cover) |
| Emergency essentials suggestion | half-up to the paisa, then half-up to the rupee |
| Subscription monthly equivalent | half-up (weekly = amount × 52 ÷ 12) |

## 2. Dates

All financial dates are **calendar dates** (local midnight, `dateOnly`). Day differences are computed in UTC to be DST-safe (`daysBetween`). Month arithmetic clamps to the month's last day and can keep an anchor day, so a bill on the 31st returns to the 31st after February (`addMonthsClamped`, `Frequency.next/nth`). "Today" always comes from an injected `Clock`.

Completed money movements (transactions, loan payments, settlements, goal and emergency-fund movements, asset valuations, opening date) cannot be dated in the future.

## 3. Ledger: cash, earmarked, available

`LedgerCalculator` (`lib/finance/ledger.dart`):

```
cash       = opening balance + Σ income − Σ expense
             (transactions dated from the profile's opening date up to today)
earmarked  = Σ goal movements + Σ emergency-fund movements   (dated up to today;
             contributions +, withdrawals −)
available  = cash − earmarked
```

- Transactions before the opening date are already part of the opening balance; future-dated items are ignored until their date.
- **Allocations** (goal and emergency-fund contributions/withdrawals) move money between *available* and *earmarked*. They never change cash, are not income or spending, and do not change net worth.
- Changing the opening balance or opening date (`profile.update`) recalculates every balance; the preview shows the old and new cash and warns if cash would fall below earmarked money.
- `available` can be negative (e.g. spending after earmarking). Actions that earmark money (`goals.contribute`, `emergencyFund.contribute`, a goal's starting amount) are limited to the current available amount. Expenses larger than available are allowed but warned about.

### What is a transaction

A `Transaction` is a completed movement of cash. Not transactions: projected subscription charges, pending obligations, and internal allocations.

`TransactionOrigin` marks transactions created by another module (`loanRepayment`, `loanDisbursement`, `pendingSettlement`, `subscription`) with `originRefId` pointing to the source record. Linked transactions can only be changed through that module, so a repayment or settlement is never counted twice.

### Cash-flow analytics

`CashFlowCalculator.summarize(range)` (inclusive range):
- **income** excludes loan disbursements (borrowing is not income);
- **expense** excludes money lent out, but includes EMIs and settlements paid;
- per-category and per-payment-method totals are sorted descending (missing method = "Other");
- savings rate = (income − expense) ÷ income in bps; `null` with no income.

Whole calendar months are compared with the previous calendar month; other ranges with the same number of days immediately before (`AnalyticsService.compare`).

## 4. Budgets

`BudgetCalculator` (`lib/features/budgets/domain/budget_calculator.dart`). Budgets are spending **limits**; they hold no money.

- Period: monthly, starting on the user's month start day (clamped to 1–28), or a custom range of at most 366 days.
- **spent** = expense transactions in the budget's category within the period (loan disbursements excluded).
- **committed** = expected subscription charges in that category from today to the period end. Shown separately, never added to spent.
- Health: `paused` → `breached` when spent > limit → `warning` when spent ÷ limit ≥ warning threshold (exact integer comparison, so 79.999% is not 80%) → `healthy`.
- Warning threshold 50–95%, default 80%. Only one *active* monthly budget per category; a paused budget frees the category.

## 5. Savings goals

`GoalCalculator` (`lib/features/goals/domain/goal_calculator.dart`). A goal's saved amount is derived from its `SavingsMovement`s (dated up to today), never edited directly.

- progress = saved ÷ target (bps, clamped to 0–100%); achieved when target > 0 and saved ≥ target.
- average monthly contribution = net movements in the last **three full calendar months** ÷ 3; `null` without any history before the current month.
- required per month = remaining ÷ months to the target date (partial month counts as one; everything if the date is this month or past).
- estimated completion = today + ⌈remaining ÷ rate⌉ months, where rate is the planned monthly contribution if set, else the average. No estimate for zero/negative rates or more than 600 months.
- on track = estimate ≤ target date; `null` when unknown.
- Withdrawals are limited to the saved amount. Archiving keeps money earmarked. Deleting a goal deletes all its movements (including future-dated ones), releasing the money to available.

## 6. Emergency fund

`EmergencyFundCalculator` (`lib/features/emergency_fund/domain/`).

- target = essential monthly expenses × target months (1–24), or an explicit override.
- saved = emergency-fund movements dated up to today.
- coverage = saved ÷ essentials, in tenths of a month, rounded down.
- level: `notConfigured` (no plan or target ≤ 0) → `funded` (saved ≥ target) → `critical` (coverage < 2.0 months) → `building`.
- Suggested essentials = average of essential-category expenses plus EMIs over the last three full months. It is only a suggestion; it is never applied without the user saving a plan.

## 7. Loans

`LoanCalculator` (`lib/features/loans/domain/loan_calculator.dart`). Directions: **borrowed** (liability) or **lent** (receivable). Structures: **amortizing** (EMI) or **interest-only**.

- Periodic interest = outstanding × annual rate ÷ periods per year, half-up to the paisa. No daily accrual. Rates are basis points (0–60% p.a.).
- EMI (exact): `P · r · (1+r)^n ÷ ((1+r)^n − 1)` with `r = bps ÷ (10000 × periods/yr)`, evaluated with `BigInt` as `P·bps·(d+bps)^n ÷ (d·((d+bps)^n − d^n))`, `d = 10000 × periods/yr`; rounded up to the paisa, then up to the rupee. Example: ₹6,00,000 at 9.5% for 60 months → ₹12,602.
- Schedule: each row pays the period's interest first, the rest reduces principal; the final instalment is reduced so the balance ends at exactly zero. Due dates keep the first due date's day.
- Outstanding = principal − Σ principal repaid. Overdue = scheduled rows due before today that are unpaid.
- Payment rules (`previewPayment`): an EMI/interest payment must cover the interest due and may not exceed the payoff (interest due + outstanding); paying more than the EMI is flagged as a prepayment. A principal repayment cannot exceed the outstanding. A payment that brings outstanding to zero closes the loan.
- Prepayment strategy: `reduceTenure` keeps the EMI and finishes earlier; `reduceEmi` recomputes the EMI over the remaining instalment count.
- Interest-only loans: each period's payment is the interest; principal is due with the period that reaches the maturity date (if any). Interest-free loans without a maturity have nothing scheduled.
- Disbursements are optional cash movements (borrowed: cash in; lent: cash out). They are not income or spending. Loan terms are locked once a payment exists; a loan with payments cannot be deleted.
- Weekly repayment is not supported; tenure is 1–480 instalments.

## 8. Subscriptions

- Monthly equivalent: weekly × 52 ÷ 12, monthly as is, quarterly/half-yearly/yearly ÷ months (half-up). Commitment totals count active subscriptions only.
- Upcoming renewals are **projections**, not transactions. Marking a cycle paid creates one linked expense (default date: the due date, or today if that is ahead) and advances the next due date by one cycle; each cycle can be paid only once. Skipping a cycle advances the date without a transaction.
- Due states: overdue (past due, unpaid) / due today / due soon (within the reminder window) / upcoming.

## 9. Pending payments (owed to / by others)

- Creating an obligation never changes cash. Only settlements can, through an optional linked transaction (`Settlement Paid` / `Settlement Received` system categories).
- outstanding = original − Σ settlements (zero when cancelled/written off). Status: open → partially settled → settled, or cancelled. A settlement cannot exceed the outstanding amount.
- Overdue = active with a due date before today.

## 10. Net worth

`NetWorthCalculator` (`lib/features/net_worth/domain/net_worth.dart`):

```
net worth = cash + assets + receivables − liabilities
receivables = outstanding principal of lent loans + pending to collect
liabilities = outstanding principal of borrowed loans + pending to pay
```

Cash is counted once: earmarked goal and emergency savings are part of cash and are shown only as a split. Assets are user-entered valuations; cash tracked in FiNN is never also an asset. Loans with nothing outstanding are omitted.

## 11. Alerts

`AlertEngine` (`lib/features/alerts/domain/alert_engine.dart`) derives the "What needs attention" list from a snapshot and settings. Keys are deterministic (type + record + period), so read/dismissed state survives regeneration. Sort: severity (critical, warning, info, positive), then due date (dated first), then key.

| Alert | Condition | Severity |
|---|---|---|
| Overdue EMI | next instalment due before today | critical (borrowed) / warning (lent) |
| Upcoming EMI | due within `emiReminderDays` (default 5) | warning |
| Pending overdue / due soon | due date passed / within `pendingReminderDays` (3) | critical if I owe and overdue, else warning |
| Money to collect (aged) | owed to me, no due date, open > 30 days | info |
| Unpaid subscription | due date passed, not marked paid | warning |
| Subscription renewal | due today or within `subscriptionReminderDays` (3) | info |
| Budget near limit / exceeded | health warning / breached in the current period | warning / critical |
| Emergency fund not set | no plan and the user has any activity | info |
| Low emergency fund | coverage below `lowEmergencyCoverageMonths` (3) | warning if critical level, else info |
| Goal funded / 75% funded | achieved / progress ≥ 75% | positive |
| Goal behind schedule | not on track, target date within 365 days | info |
| Spending above income | this month's expense > income (and income > 0) | warning |

Any alert type can be switched off in notification settings.
