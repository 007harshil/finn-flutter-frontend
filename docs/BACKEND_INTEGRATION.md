# Backend integration

FiNN ships with a local mock backend. Features depend only on repository interfaces and on the action layer, so a real API can replace the mock without changing screens or calculators. This guide describes what exists today and how to swap it.

## What exists today

| Piece | Location | Role |
|---|---|---|
| Repository contracts | `lib/domain/repositories.dart`, `lib/core/data/crud_repository.dart` | One interface per entity |
| Repository bundle | `lib/domain/finance_repositories.dart` | `FinanceRepositories` + `loadSnapshot()` |
| Swap point | `financeRepositoriesProvider` in `lib/app/di/core_providers.dart` | Builds the bundle from `LocalDataStore` |
| Mock implementation | `lib/data/local/local_data_store.dart` | `EntityCollection` / `ValueStore` persisted as JSON in SharedPreferences |
| Serialization | `lib/data/dto/dtos.dart` | `XxxDto.toJson / fromJson` for every entity |
| Seed data | `lib/data/mock/seed_data.dart` | `demo`, `empty`, `stressed` scenarios |
| Failure model | `lib/core/result/result.dart` | `AppFailure` + `FailureCode` |

Note: the header comment in `repositories.dart` mentions `lib/app/di/repository_providers.dart`; that file does not exist. The real swap point is `financeRepositoriesProvider`.

### Contracts

```dart
abstract interface class CrudRepository<T> {
  Stream<List<T>> watchAll();   // emits the current list immediately, then on every change
  Future<List<T>> getAll();
  Future<T?> getById(String id);
  Future<void> save(T item);    // upsert by id
  Future<void> saveAll(Iterable<T> items);
  Future<void> delete(String id);
}

abstract interface class ValueRepository<T> {  // profile, emergency plan, alert inbox
  Stream<T> watch();
  T get current;                // synchronous: must be hydrated before first use
  Future<void> set(T value);
}
```

Collections: transactions, categories, budgets, goals, savings movements, loans, loan payments, subscriptions, pending payments, settlements, assets, shared ledger (mirrors of shared pending items). Single values: financial profile, emergency-fund plan, alert inbox (read/dismissed alert keys; UI bookkeeping, may stay local).

## Swapping in a real API

1. **Implement the interfaces.** For each entity, write e.g. `RemoteTransactionRepository implements TransactionRepository`. Keep an in-memory cache and a broadcast stream so `watchAll()` emits immediately and after every successful write. The UI and snapshot rely on that behaviour.
2. **Reuse the DTOs.** `dtos.dart` is the wire format starting point:
   - money as integer paise (`amountPaise`, `principalPaise`, …);
   - calendar dates as `yyyy-MM-dd`, instants as ISO-8601;
   - enums by `name`;
   - a `version` integer on mutable records (optimistic concurrency).
   If the API's shape differs, add mappers next to the DTOs instead of changing domain models. Domain models never know about JSON.
3. **Provide the bundle.** Override `financeRepositoriesProvider` in the `ProviderScope` (`lib/main.dart`) with a bundle of remote repositories. `localDataStoreProvider` is then unused. Nothing else changes: `financeSnapshotProvider`, every derived provider, and `actionEnvironmentProvider` all read the bundle.
4. **Hydrate single values.** `ValueRepository.current` is read synchronously by `loadSnapshot()` and by actions. Fetch the profile and emergency plan before the first frame, as `main.dart` does today with `store.open(...)`.
5. **Map errors to `AppFailure`.** Throw `AppFailure` from repositories. The dispatcher turns it into `ActionRejected`; any other exception becomes `FailureCode.unknown` ("Nothing was changed", retryable). Suggested mapping:

| HTTP / transport | `FailureCode` |
|---|---|
| 400 / 422 with field errors | `validation` (fill `fieldErrors` with input field names) |
| 404 | `notFound` |
| 409 version mismatch, 412 | `staleData` |
| 409 other | `conflict` |
| 409 idempotency key in flight | `duplicate` |
| 403 | `notPermitted` |
| timeout, 5xx, offline | `unavailable` (`retryable: true`) |

6. **Test against the same suites.** `test/actions/action_harness.dart` builds `FinanceRepositories` explicitly; point it at the new implementations (or a fake server) and run `flutter test test/actions`. `MockBehavior` (latency, failing reads/writes) shows how the UI behaves under slow or failing storage.

## Things a backend must preserve

- **Exact money.** Store paise as integers (or fixed-point decimals). Never floats.
- **Client-generated ids.** Ids are created on the device (`RandomIdGenerator`: `prefix_<time36><rand36>`) and referenced across records: `Transaction.originRefId`, `LoanPayment.transactionId`, `PendingSettlement.transactionId`, `Loan.disbursementTransactionId`. Accept client ids, or remap every reference when assigning server ids.
- **Optimistic concurrency.** Update actions compare `expectedVersion` with the record in the snapshot and increment `version` on save. A server should enforce the same check and reject stale writes.
- **Derived values stay derived.** Balances, goal saved amounts, loan outstanding, budget spending, alerts and net worth are computed on the client from records (`FinanceSnapshot`). Do not store them as editable fields. If a server computes them too, it must follow `docs/FINANCIAL_MODEL.md` exactly (same rounding).
- **Linked transactions.** Transactions with a non-manual `origin` belong to their source record and must be written and deleted together with it.

## Shared pending payments (double entry)

A pending item whose counterparty is a FiNN user is shared: it lives in both accounts, mirrored. If Aarav records "I owe Ramesh ₹1,000", Ramesh's account holds "Aarav owes me ₹1,000". Both entries carry the same `PendingLink.sharedId`. Pending items have no due dates; only age ("40 days have passed") is shown.

- **Contracts** (`lib/domain/repositories.dart`): `UserDirectory` (`me`, `search(query)`, `known(id)`) and `SharedLedgerRepository` (one `MirrorEntry` per counterparty and shared item). The local mock is `LocalUserDirectory` over `lib/data/mock/finn_users.dart` plus the `shared_ledger` collection.
- **Search.** The form debounces typing (350 ms) before calling `search`; queries shorter than 2 characters return nothing. A backend search should return only name, handle and a phone hint, and be rate limited.
- **Sync.** Every pending action calls `syncSharedPending` (`pending_actions.dart`) after its own write. It rebuilds the counterparty's mirror from the saved item and its settlements (`mirrorOf`): direction reversed, borrowed ↔ lent, counterparty = `me.name`. Delete removes the mirror. A backend should do this server-side in the same transaction (or via an outbox) and push the change to the other user.
- **Rules.** Only the creator (`link.createdByMe`) edits details or deletes. Either person records settlements. Only the person who is owed can write the rest off. The person on a shared item never changes. Mirrored settlements never create cash transactions for the other person; their own app decides that.

## Atomicity

Some actions perform several repository writes:

| Action | Writes |
|---|---|
| `loans.create` with disbursement | transaction, then loan |
| `loans.recordPayment` | transaction, loan payment, loan status (transaction removed again if a later write throws) |
| `loans.delete` | disbursement transaction, then loan |
| `goals.create` with a starting amount | goal, then savings movement |
| `goals.delete` | every movement of the goal, then the goal |
| `pending.settle` | linked transaction, then settlement (transaction removed again if the second write throws) |
| `subscriptions.markPaid` | linked transaction, then the subscription's next due date (same compensation) |

With the local store these cannot fail halfway in practice. With a remote API they can. Two options:

- **Recommended:** expose one server endpoint per action (see below) so each operation is a single server-side transaction.
- Otherwise, make the remote repositories idempotent upserts and accept that a failed multi-write may need a retry. The dispatcher releases the idempotency key on failure, so the user can retry the same request.

## The action layer as an API

Every write already has a transport-neutral shape, which maps directly onto an RPC-style API or LLM tools:

- **Discovery.** `ActionRegistry.describe()` returns each action's id, module, title, description, risk, `movesMoney`, `reversible` and field specs (name, kind, required, allowed values). Feed it to an agent as tool definitions, or publish it as an API schema.
- **Input.** `ActionInput.toJson()` / `FinancialAction.decode(json)`. Action JSON uses rupees as decimal strings (`"1250.50"`) or numbers, and dates as `yyyy-MM-dd`; `decode` rejects malformed input with field-level `validation` failures. (DTOs, by contrast, store paise.)
- **Two-step execution.** `dispatch` without a confirmation returns `ActionNeedsConfirmation(preview)` for consequential actions and for every agent/voice request. The preview has a human summary, lines, warnings and a `fingerprint`. The caller shows it to the user and dispatches again with `ActionConfirmation(fingerprint)`. Changed input or a changed record yields a different fingerprint, so an old approval cannot be replayed.
- **Idempotency.** Send the same idempotency key on retries. Today the key map lives in memory in `OperationDispatcher` (last 500 keys). A server should persist keys per user, return the stored result for a repeated key, and reject a reused key with a different request (`conflict`).
- **Policy.** `ActionPolicy` decides per channel (`ui`, `agent`, `voice`, `import`, `system`). The default policy forbids deletes from agent/voice and allows only `*.create` for imports. Server-side enforcement should mirror it.
- **Audit.** `AuditLog` is in memory (Settings → Activity log). Persist entries server-side for a durable history.
- **Plans.** `PlanExecutor` validates multi-step requests ("pay Rahul 500 and add 2,000 to my Japan goal"), runs only approved steps, skips dependants of failed steps and reports stale approvals. There is no cross-step rollback; each step commits on its own.
- **Name resolution.** `PendingResolver` (`pending_actions.dart`) finds an obligation by counterparty name and refuses to guess when several match (`ambiguous`).

A server implementation can host the same `FinancialAction` classes (they depend only on `FinanceRepositories`, `Clock` and `IdGenerator` through `ActionEnvironment`), or reimplement them behind endpoints such as `POST /actions/{id}:preview` and `POST /actions/{id}:execute` with the idempotency key and confirmation fingerprint as headers.

## Checklist

- [ ] Remote repositories implement every interface in `repositories.dart`; `watchAll()` emits immediately.
- [ ] DTO mapping round-trips every field, including `version` and `origin`/`originRefId`.
- [ ] `financeRepositoriesProvider` overridden; profile and emergency plan hydrated before first use.
- [ ] Errors mapped to `AppFailure` codes.
- [ ] Server enforces versions, idempotency keys and channel policy.
- [ ] Multi-write actions made atomic (per-action endpoints) or safely retryable.
- [ ] `flutter test` passes against the new implementation.
