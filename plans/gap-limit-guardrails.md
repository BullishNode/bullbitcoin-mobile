# Gap-Limit Guardrails (Recovery v2 — Phase G, detailed plan)

**Status:** PLAN — implementation-grade detail for Phase G of `bullnym/plans/recovery-v2.md` §3.
**Repo:** `bullbitcoin-mobile` (wallet-wide; NOT recovery-specific — recovery v2 R2 merely adds
one more reservation on top and must not ship on an unbounded loop).
**Written against:** branch `pr29-getpaid-stuck-swap-recovery` (stacked on `origin/pr28-getpaid-hub`).

---

## 1. The bug class

Every address index that is **issued but never funded** is a permanent "unused" hole in the
derivation chain. Wallet restore scans the chain and **stops after `stopGap` consecutive unused
scripts** (BIP44 gap limit). If ≥ stopGap consecutive never-funded indexes accumulate *below* a
funded index, that funded index — and every coin on it — is invisible after restore. Funds are
not lost (a larger gap or full rescan finds them) but to a merchant restoring on defaults, or
restoring the same seed into Sparrow/Electrum (default gap 20), **they have disappeared**. That
is a critical severity bug in a wallet.

Two independent growth mechanisms exist today:

1. **Reservation skipping** — the generate loop walks past system-labelled indexes with no
   bound, and each reserved-but-never-funded index (an unpaid invoice, an unfunded swap claim
   address) is a permanent hole.
2. **Eager revealing** — the BDK path calls `revealNextAddress` + persists on **every**
   `getNewAddress` call, so repeated fresh-address requests advance the pointer even when no
   address is ever funded.

---

## 2. Verified current state (all anchors checked on the branch)

| Fact | Anchor |
|---|---|
| The skip loop is **unbounded**: `while (labels.any(isSystemLabel)) { index++; … }`, no gap accounting anywhere in the repository | `lib/core/wallet/data/repositories/wallet_address_repository.dart:126-141` |
| BDK `getNewAddress` = `revealNextAddress` + `saveWallet` (persists the advance on every call) | `lib/core/wallet/data/datasources/bdk_wallet_datasource.dart:482-500` |
| BDK exposes `isAddressUsed(address, wallet)` (the funded/used primitive) and `peekAddress` via `getAddressByIndex` (non-advancing) | `bdk_wallet_datasource.dart:568`, `:550-566` |
| BDK exposes `getLastRevealedAddressIndex` (reveal-in-memory, not persisted — read-only) and `getLastRevealedAddressOrNew` (reuses the last revealed **unused** address) | `bdk_wallet_datasource.dart:502-548` |
| LWK exposes `addressLastUnused()` — first unused after the last **used** index (the funded-frontier signal for Liquid) | `lwk_wallet_datasource.dart:146-150` |
| Labels are the reservation store: `LabelsFacade.fetchByReference / store / trash`; labels reference the **address string**, not the index | `lib/features/labels/labels_facade.dart:47-95` |
| `LabelSystem` members today: `swaps, autoSwap, payjoin, selfSpend, exchangeBuy, exchangeSell, invoice` (`recovery` arrives with v2 R2) | `lib/features/labels/domain/primitive/label_system.dart` |
| Invoices release reservations **only on create-failure** (`_releaseReservations` → `labels.trash`); nothing releases on expiry/cancel | `lib/features/invoices/application/usecases/create_invoice_usecase.dart:53,125,195-199` |
| `stopGap` is per-Electrum-server, **user-configurable**; the settings UI treats ≤20 as the normal case and rejects >1000 | `electrum_settings` model/adapters; `set_advanced_options_bottom_sheet.dart:93,216` |

**Callers of the two repository generate APIs** (impact matrix, §6):

| Caller | Site | Nature |
|---|---|---|
| Receive screen | `lib/core/wallet/domain/usecases/get_receive_address_usecase.dart:19` | user-initiated |
| Invoices (BTC + Liquid reservation) | `create_invoice_usecase.dart:155,176` | user-initiated |
| DCA setup | `lib/features/dca/domain/usecases/set_dca_usecase.dart:57` | user-initiated |
| Recovery (PR29 legacy path; v2 R2 registration) | `recover_stuck_payment_usecase.dart:147` | user-initiated |
| **Swap watcher (claim destinations)** | `lib/core/swaps/data/services/swap_watcher.dart:733,762,776` | **automated, money-critical** |

---

## 3. Design

### The invariant

> No code path may issue (or reserve) a receive index that would create a run of more than
> **`GAP_HARD_BOUND = 15`** consecutive never-funded indexes, except the best-effort fallback
> in §3.3 — and that fallback *reuses* an address rather than widening the run.

**Why 15, and why not derived from the configured `stopGap`:** the binding constraint is not
this app's scanner (which we control and could raise) but **external restore** — the same seed
in Sparrow/Electrum/etc. with the BIP44-conventional gap of 20. A user-raised local `stopGap`
of 1000 must NOT license a 995-wide hole that bricks external restore. So the bound is the
conservative constant `20 − margin(5) = 15`, independent of local settings. (Open question Q1:
whether to let a raised local stopGap raise the bound behind an "I understand external restore
breaks" setting — default NO.)

### G1 — bound issuance (critical)

**Where:** `wallet_address_repository.dart`, both `generateNewReceiveAddress` and
`generateNewLiquidReceiveAddressWithBlindingKey` (the skip loops AND the initial candidate).

**Algorithm — the window check** (uniform for BDK and LWK, stateless, cheap):

```
isWithinGapBound(candidateIndex, wallet):
  if candidateIndex < GAP_HARD_BOUND: return true       // low indexes are always safe
  for i in candidateIndex-1 downto candidateIndex-GAP_HARD_BOUND:
    if isAddressUsed(addressAt(i)): return true          // a funded index inside the window
  return false                                           // 15+ consecutive never-funded below
```

- BDK: `addressAt` = `getAddressByIndex` (peek, non-advancing); `isAddressUsed` exists.
- LWK: short-circuit first via `addressLastUnused()` — if
  `candidateIndex − lastUnused.index ≤ GAP_HARD_BOUND` the window check is already satisfied
  (lastUnused−1 is used by definition); fall back to the window walk only past that.
- Cost: ≤15 local peek+used lookups, only on generate (rare), no new persistent state, no new
  tables. Deliberately chosen over "track highestFundedIndex" state, which can drift.

**Enforcement points:**
1. The initial candidate (BDK `getNewAddress` result / LWK `lastUnused+1`).
2. Every iteration of the skip loop (`index++` may only proceed while within bound).

**On violation — two policies** (new enum param, default `strict`):

```dart
enum GapPolicy { strict, bestEffortReuse }

Future<WalletAddress> generateNewReceiveAddress({
  required String walletId,
  GapPolicy gapPolicy = GapPolicy.strict,
})
```

- `strict` → throw new typed error `WalletError.gapLimitPressure(walletId, candidateIndex)`
  (added to the existing `WalletError` family). User-initiated callers surface copy:
  *"Too many unpaid or reserved addresses. Wait for payments to arrive or clear unpaid
  invoices, then try again."*
- `bestEffortReuse` → **never fail, never widen**: return the last revealed **unused,
  unreserved** address instead (BDK: `getLastRevealedAddressOrNew` semantics with a
  label-check; LWK: `addressLastUnused`). Address *reuse* is a privacy cost; a failed swap
  claim or a widened gap are both worse. Log `log.severe` (Sentry-tagged) so pressure is
  visible in telemetry either way.

**Policy per caller (§6 matrix):** swap watcher = `bestEffortReuse` (its three sites are claim
destinations — the claim MUST proceed); all other current callers = `strict`.

### G2 — release-on-expiry/cancel (the biggest accumulator)

Unpaid invoices are the dominant source of permanent holes: every expired invoice leaves its
reserved BTC and/or Liquid index labelled forever.

- **Persist the reservation link:** the invoices feature currently keeps `reservedLabelIds`
  only in-memory during create. Add `reservedLabelIds` (JSON list, nullable) to the local
  invoice bookkeeping the feature already writes, so release is possible later. (If the
  feature genuinely persists nothing per-invoice — its charter forbids an invoice store — the
  fallback is label-origin-based release: invoice labels are stored with
  `origin: 'invoice:<id>'`; release = `fetchAll` filter by origin prefix + terminal status.)
- **Hooks:**
  - `CancelInvoiceUsecase` success → release that invoice's reservation labels (`labels.trash`).
  - List/status reconciliation (`InvoicesListCubit` refresh / detail poll) → any invoice seen
    in a terminal unfunded state (`expired`, `cancelled`, and NOT paid) → release its labels,
    idempotently.
- **Never release a funded reservation** (paid invoice): the label then serves attribution —
  release only when `isAddressUsed == false`.
- A released never-funded index re-enters circulation via the (now bounded) skip loop; reuse
  of a never-funded address is privacy-harmless.

### G3 — outstanding-reservation cap (belt-and-braces)

Before storing any **new** reservation system label on a receive address:
`count(system-labelled addr labels of this wallet whose address is unused) ≥ RESERVATION_CAP
(default 10)` → refuse with the same `gapLimitPressure` surface. Computed on demand
(`labels.fetchAll()` filter + `isAddressUsed`) — reservation creation is rare; no cache
needed. Implemented as a small helper in the labels or wallet layer, called by the invoices
reservation step and the R2 recovery registration.

Note `10 < 15` deliberately: the cap keeps *reservations* from ever being the sole cause of a
bound violation, leaving headroom for organically-unpaid plain receive addresses.

### G4 — restore-side notes (docs + verification, no code)

- The recovery address (v2 R2) contributes exactly **+1** never-funded index, allocated at
  provisioning while the cursor is low — constant, safe under the bound. Spec line repeated
  from v2: *recovery MUST NOT derive per-swap addresses.*
- After seed restore, labels are gone; the Get Paid heal re-asserts the `recovery` label
  (v2 R2). Invoice reservation labels are NOT re-asserted after restore — acceptable: their
  indexes simply re-enter circulation, which is the G2 end-state anyway.
- Document for support: a merchant restoring into an external wallet should be told funds are
  complete because the app enforces the 15-bound; if a legacy wallet (pre-G1) shows missing
  funds, the fix is raising the gap limit / rescan.

---

## 4. Exact code changes

| File | Change |
|---|---|
| `lib/core/wallet/data/repositories/wallet_address_repository.dart` | Add `GapPolicy`; add `_isWithinGapBound(...)` (window check); enforce at initial candidate + in both skip loops; `bestEffortReuse` fallback path; constants `gapHardBound = 15` |
| `lib/core/wallet/domain/…/wallet_error.dart` (existing `WalletError` family) | Add `gapLimitPressure` variant + copy key |
| `lib/core/swaps/data/services/swap_watcher.dart:733,762,776` | Pass `GapPolicy.bestEffortReuse` |
| `lib/features/invoices/application/usecases/create_invoice_usecase.dart` | Catch `gapLimitPressure` → typed `InvoicesException` (new kind), l10n copy; call the G3 cap check before reserving |
| `lib/features/invoices/application/usecases/cancel_invoice_usecase.dart` + list/status reconciliation | G2 release hooks (origin-prefix based) |
| `lib/features/dca/domain/usecases/set_dca_usecase.dart`, `get_receive_address_usecase.dart`, `recover_stuck_payment_usecase.dart` | No signature change (strict default); surface the typed error in their existing error mapping |
| `localization/app_en.arb` | `walletErrorGapLimitPressure`, invoice-facing variant |
| Reservation-cap helper | Small `countOutstandingReservations(walletId)` — home: labels facade extension or wallet repository; used by invoices + R2 registration |

**Explicitly out of scope:** changing BDK `getNewAddress`'s reveal-persist behavior (mechanism
2 in §1) — the bound makes it harmless (reveals past the bound are refused/reused); altering
it would touch every BDK flow for little gain. Recorded as Q3.

---

## 5. Tests

**Unit — repository (fake BDK/LWK datasources + fake labels facade):**
1. Candidate within bound → issued (baseline).
2. 15 consecutive never-funded below candidate → `strict` throws `gapLimitPressure`; nothing
   revealed/persisted.
3. Same state, `bestEffortReuse` → returns last revealed unused address, run NOT widened,
   severe log emitted.
4. Skip loop: reservations push candidate toward the bound → loop stops with the typed error
   at the bound, not beyond (regression for the unbounded `while`).
5. A funded index inside the window resets safety (window check correctness — funded at
   `candidate−15` exactly: pass; at `candidate−16`: fail).
6. LWK short-circuit: `candidate − lastUnused ≤ 15` skips the walk.
7. G3: cap at N reservations → N+1th refused; funded reservations don't count.
8. G2: cancel/expired reconciliation trashes only unfunded reservation labels; paid invoice's
   label survives; release is idempotent.
9. Regression (v2 tie-in): 1 recovery label + (cap) invoice labels never trips G1 on a wallet
   with normal funding activity.

**Existing-suite impact:** invoices usecase tests gain the two new error-path cases; recovery
44-suite unaffected (strict default preserves behavior below the bound); lifecycle spec
unaffected (fresh DB, low indexes).

---

## 6. Rollout & acceptance

Single PR (it is one invariant), reviewable in three commits: (1) G1 + tests, (2) G2 + tests,
(3) G3 + copy/l10n.

**Acceptance:**
- No code path can create a >15 run of never-funded indexes; violation is either a typed,
  user-explained failure (strict) or a logged address-reuse (bestEffortReuse). Verified by the
  unit matrix above.
- Swap claims cannot fail due to gap pressure (bestEffortReuse at all three watcher sites).
- Cancelling or letting an invoice expire frees its reserved indexes (observable: a
  subsequent generate hands out a previously-reserved index).
- `flutter analyze` clean; all suites green.

**Sequencing vs recovery v2:** G ships before or with R2 (R2 adds the `recovery` label — its
registration path calls the G3 cap check and relies on G1 being in place). G is independently
valuable and can land regardless of the v2 debate.

**Effort:** G1 M (the window check + two datasource touchpoints + policy plumbing),
G2 S–M (hooks + origin-based release), G3 S. Total ≈ M.

---

## 7. Open questions

1. Should a user-raised local `stopGap` raise the bound (behind an explicit "external restore
   may miss funds" acknowledgement)? Proposed: **no** — constant 15.
2. `RESERVATION_CAP` default 10 — is that enough for a busy merchant issuing many concurrent
   unpaid invoices? (G2 release makes steady-state pressure low; the cap only binds bursts.)
3. Leave BDK reveal-on-every-`getNewAddress` as-is (bounded but eager)? Proposed: yes (§4).
4. Telemetry: is `log.severe` on `bestEffortReuse` enough, or do we want a visible in-app
   "address reuse occurred" note for the privacy-conscious? Proposed: log only.
5. G2 origin-prefix release requires invoice labels to carry `origin: 'invoice:<id>'` — verify
   the existing `NewLabel.addr(origin: …)` value; if it lacks the id, add it (new labels only;
   legacy labels release via the terminal-status sweep matching by address).
