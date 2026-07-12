# POS Stuck Chain-Swap Payment: Detection + Merchant Recovery (mobile)

> **MODEL SUPERSEDED (2026-07-10):** the recovery *model* in this plan (manual one-tap as the
> primary executor, per-recovery default-wallet address derivation, out-of-band settle-at-the-till
> for all surfaces) is superseded by **`bullnym/plans/recovery-v2.md`** ("server settles, phone
> supervises"): single registered recovery address, server auto-recovery, confirmation-gated
> finality, settlement accounting, gap-limit guardrails. The WIRE LAYER, detection endpoint,
> Drift store, echo-adoption, and UI built under this plan all carry forward (v2 §4 mapping);
> one-tap becomes the legacy/exception fallback.

**Branch:** `pr28-getpaid-hub` — this plan is written against
**`origin/pr28-getpaid-hub` @ `5833ad48b62a119dbfe8601ea73aa0683c8a1a83`**
("refactor(get-paid-settings): migrate the settings screen to bull_ui", 2026-07-07). Server
citations are against the bullnym working tree @ `a40bd6b3c5abd86dbc2a29503f548c03582300be`.
**Server recovery endpoint:** bullnym `POST /api/v1/:nym/invoices/:id/recover`
(`recover_chain_swap`, `src/invoice.rs:1093`). **Status:** implementation plan, no code yet.

> **HARD PREREQUISITE (blocking for all detection work):** the paired bullnym server spec
> `/home/francis/bull-bitcoin-workspace/bullnym/plans/chain-swap-recovery-detection-server.md`
> (WRITTEN, in review) must land and deploy first. It adds a **dedicated signed detection
> endpoint** `GET /api/v1/invoices/recoverable` (action `invoice-recovery-list`) returning the
> npub's recoverable chain swaps — it does NOT touch `invoice-list`. §2.3 pins the exact response
> shape this client consumes. Phase 1 (wire/signing) can proceed against the recover endpoint,
> which already exists; Phases 2+ cannot ship without this new detection endpoint.

## 1. Goal

When a customer pays a POS (or Payment Page) invoice with Bitcoin on-chain, the payment rides a
Boltz chain swap. If that swap fails after the customer funded the lockup, the bullnym server
parks the swap in `refund_due` and the BTC is stranded until the **nym key-holder** — this mobile
app, and only this app (there is no operator/CLI signing path) — signs an `invoice-recover`
request. The app must:

1. **Detect** that a payment is stuck and tell the merchant.
2. **Recover** the stranded BTC to a fresh address in the merchant's own default Bitcoin wallet,
   with minimal manual steps, driving the swap `refund_due -> refunding -> refunded`.
3. Make explicit that "recovered" means the merchant got the BTC — **the payer must be made whole
   out-of-band at the till**; the app's job is to say so, loudly.

## 2. Settled model + server contract

### 2.1 Which invoices can be stuck — SETTLED, no hedging

Payment Page and POS checkout invoices are **nym-linked**: created keyless (no merchant
signature is needed to create one at checkout) but **owned** — the server writes
`nym_owner: Some(&nym)`, `npub_owner: &owner.npub`, `origin: "checkout"` (`src/invoice.rs:566`).
They are the **only** invoices that ever get chain swaps: `create_bitcoin_chain_offer`
(`src/invoice.rs:1624`) has exactly one call site, in the keyless checkout path
(`src/invoice.rs:616`). Wallet-origin `invoice-create` invoices (the `features/invoices` flow,
linked or not) get **no** chain swaps and are permanently out of scope for recovery.

Consequences the design leans on:

- The recoverable-and-detectable universe = the merchant's own Payment Page + POS checkout
  invoices, all owned by the merchant's npub, so every recovery-lifecycle swap of theirs is
  returned by the signed, npub-scoped detection endpoint (§2.3). The POS PWA's browser-local
  history is irrelevant: the signed `invoice-recovery-list` response is the watch-set source of
  truth.
- The recover endpoint's ownership gate (`inv.npub_owner == req.npub` AND
  `inv.nym_owner == Some(path nym)`, `src/invoice.rs:1140-1147`) is satisfiable for the entire
  recoverable population using the same Get Paid identity the app already derives.

### 2.2 Detection auth — SETTLED, no hedging

The merchant learns of a stuck swap **only** via a SIGNED, npub-scoped, ownership-verified path
(`verify_la_v2`). The anonymous public `GET /api/v1/invoices/:id/status` endpoint stays coarse
for payers and **must not** be used for recovery detection or recovery-progress polling — it will
never expose `refund_due`/`refunding` (the server spec §4 guarantees the non-leak structurally),
and no code in this plan reads recovery state from it. (The unsigned status endpoint remains fine
for what it already does elsewhere: payer-facing invoice payment status.)

### 2.3 Detection signal — the dedicated `invoice-recovery-list` endpoint (server spec)

Today bullnym exposes recovery state on **no** client path: `refund_due`/`refunding` live only on
the `chain_swap_records` table (`src/db/chain_swaps.rs`), and the invoice-level
`settlement_status` enum deliberately excludes them (write-guard `src/db/invoices.rs:825` admits
only `none|pending|settled|claim_stuck|refunded|failed`). **Do not** design against
`settlementStatus` ever carrying `refund_due`, and **do not** page-walk `invoice-list` looking
for recovery state — neither carries it.

The server spec closes the gap with a **dedicated signed detection endpoint** (spec option B,
chosen precisely to avoid page-walking a merchant's whole invoice history — up to ~1000 pages —
on every poll for a signal that is almost always empty):

```
GET /api/v1/invoices/recoverable?npub=<hex>&timestamp=<unix>&signature=<schnorr hex>
```

- Action `invoice-recovery-list`, npub-keyed with **empty nym** (mirrors `list_signed`,
  `src/invoice.rs:2296`), **zero signed payload fields** (`recovery_list_payload_fields() == []`,
  spec §3.1). An npub can own swaps across multiple nyms; each row carries its own `nym`.
- Returns ALL of the npub's chain swaps in a recovery lifecycle state, **one row per chain swap**
  (not one object per invoice), plus a top-level `recovery_enabled` flag and `has_more`:

```jsonc
{
  "recovery_enabled": false,   // server's chain_swap_merchant_recovery flag; drives UI, NOT detection
  "count": 1,
  "has_more": false,           // true iff the server LIMIT (100) was hit → treat as "contact support"
  "items": [
    {
      "invoice_id": "3f6f...",
      "nym": "merchant-nym",              // build POST /api/v1/<nym>/invoices/<invoice_id>/recover
      "recovery_status": "refund_due",    // "refund_due" | "refunding" | "refunded" (chain-swap status)
      "user_lock_amount_sat": 105000,     // what the payer locked on BTC (recoverable UTXO)
      "server_lock_amount_sat": 100000,   // effective/renegotiation-aware invoice-side amount
      "lockup_address": "bc1p...",        // the funded BTC lockup (swap identity within an invoice)
      "refund_address": null,             // committed first-write-wins destination or null
      "refund_txid": null,                // broadcast recovery txid or null
      "swap_created_at_unix": 1767000000,
      "swap_updated_at_unix": 1767003600,
      "invoice": {                        // context so no page-walk is needed
        "status": "expired", "amount_sat": 100000,
        "fiat_amount_minor": 5000, "fiat_currency": "CAD",
        "public_description": "Order 123", "invoice_number": "INV-42",
        "created_at_unix": 1766990000
      }
    }
  ]
}
```

- **Detection = `items` non-empty.** No presence-flag on other endpoints, no page walk.
- **One row per swap resolves the multi-swap case natively** (was Open Question 1): an invoice
  with two recoverable swaps is two rows, keyed client-side by `(invoice_id, lockup_address)`.
- **`recovery_enabled`** is the server's `chain_swap_merchant_recovery` flag surfaced to the
  client. Detection itself is **always-on** behind Schnorr auth and is NOT gated by it (spec §7):
  merchants can SEE stranded funds before the broadcast path is enabled. The client uses the flag
  only to drive UI — `true` → "Recover now"; `false` → read-only + "Contact support" (§6, §8).
- The echoed `refund_address` + `refund_txid` on these rows ARE the **post-reinstall
  reconciliation** payload (§7): a fresh install adopts the server-committed values instead of
  deriving a new address. The recover endpoint's error shapes are unchanged (spec §6).
- The endpoint does NOT require an active registration row (unlike `recover`), so a merchant whose
  Get Paid registration lapsed can still see stranded funds. Detection therefore needs only the
  npub signer, not a nym lookup (§5.2).

### 2.4 Recover endpoint contract (exists on the server today)

- **Endpoint:** `POST /api/v1/:nym/invoices/:id/recover` — linked-only (ownership gate above).
- **Request:** `{ npub, timestamp, signature, btc_address }`. `btc_address` is the merchant's BTC
  **mainnet** address (`validate_btc_refund_address`, `src/invoice.rs:1070` — parse + mainnet
  check; the address is used RAW/untrimmed in the signed bytes).
- **Auth:** `verify_la_v2(action="invoice-recover", ...)` — the SAME `bullpay-la-v2` chain the
  client already implements in `lib/features/bullnym/domain/bullpay_signing.dart`. Signed-field
  ordering is `recover_payload_fields` (`src/invoice.rs:1815`): **`[invoice_id, btc_address]`**,
  and the `nym_or_empty` slot is the **non-empty path nym** (unlike `invoice-list`, which always
  signs `""`).
- **Semantics:** destination is **first-write-wins**, committed to the DB before broadcast
  (`set_chain_swap_refund_address`, `src/db/chain_swaps.rs:456`); retry-after-success is
  **idempotent** (same `{status:"recovered", txid}`); mid-flight retry returns
  `RecoveryInProgress`. Error codes (`src/error.rs:205-207`): `RecoveryNotAvailable`,
  `RecoveryInProgress`, `RecoveryAddressInvalid`, `InvoiceNotFound` (also used for ownership
  mismatch — never leaks cross-nym existence).
- **Gating:** server flag `features.chain_swap_merchant_recovery` is default-OFF
  (`src/config.rs:94,104`). A server without the flag/route returns a 404/unknown shape — the
  client must fail closed and keep the stuck state visible, never pretend recovery happened.

## 3. Architecture: a new `payment_recovery` feature hexagon

Follow the branch's feature-slice convention (own `domain/application/data/presentation/public` +
`*_locator.dart` + `*_architecture.md`), like `features/invoices` and `features/pos`:

```
lib/features/payment_recovery/
  payment_recovery_architecture.md
  payment_recovery_locator.dart
  domain/
    entities/stuck_payment.dart              # invoice id, nym, amountSat, fiat, detectedAt, state, refundAddress, refundTxid, lastErrorCode
    primitives/recovery_state.dart           # detected | addressCommitted | recovering | recovered | failed | dismissed
    payment_recovery_error.dart              # PaymentRecoveryException family (mirrors invoices_error.dart)
    repositories/payment_recovery_repository.dart
  application/
    ports/recovery_identity_port.dart        # signer handle (mirrors invoices_identity_port.dart)
    usecases/scan_stuck_payments_usecase.dart
    usecases/recover_stuck_payment_usecase.dart
    usecases/watch_stuck_payments_usecase.dart   # repo stream for badges
    usecases/dismiss_stuck_payment_usecase.dart
  data/
    datasources/recovery_identity_datasource.dart   # copy of InvoicesIdentityDatasource pattern
    drift_payment_recovery_repository.dart
  presentation/
    stuck_payments_cubit.dart / stuck_payments_state.dart
    stuck_payment_detail_cubit.dart / _state.dart
  public/
    payment_recovery_facade.dart
  ui/
    screens/stuck_payments_screen.dart
    screens/stuck_payment_detail_screen.dart
    widgets/stuck_payment_banner.dart
```

Why a NEW slice instead of extending `features/invoices`: the invoices charter explicitly forbids
a local store ("No local invoice store (§3.15)" in `invoices_architecture.md`), and recovery
**requires** durable local state (committed address, txid, retry bookkeeping). A separate hexagon
keeps that charter intact and keeps recovery's Drift table, background hooks, and consent
semantics out of the one-shot invoice flow. The shared wire pieces go into `features/bullnym`
exactly like the `invoice-*` actions did. (Recovery is also invoice-population-disjoint from
`features/invoices`: §2.1 — checkout invoices only.)

Register in `lib/locator.dart` after `InvoicesLocator.setup(locator)` and before
`GetPaidLocator.setup(locator)` (`lib/locator.dart:110-113`), since the Get Paid dashboard cubit
consumes the recovery facade: `PaymentRecoveryLocator.setup(locator);`.

## 4. Wire + signing extension (shared `bullnym` feature)

All in the existing files; mirror the `invoice-cancel` flow end-to-end. Note two branch-tip
facts: (a) the base URL constants moved to `lib/features/bullnym/public/bullnym_config.dart`;
(b) timestamps are injectable — `BullnymHttpClient` signs invoice actions with its constructor
`_nowSecs` (default `currentBullpayTimestampSecs`), and `BullnymLocator` wires the app-wide
`Clock` into `BullnymFacade(nowSecs: () => locator<Clock>().nowSecs())`. The new method follows
the existing pattern (client-side signing, so `recoverChainSwap` needs no facade-level timestamp
plumbing).

1. **`lib/features/bullnym/domain/bullnym_invoice_actions.dart`**
   ```dart
   const String bullpayActionInvoiceRecover = 'invoice-recover'; // server ACTION_RECOVER, src/invoice.rs:66
   const String bullpayActionInvoiceRecoveryList = 'invoice-recovery-list'; // server ACTION_RECOVERY_LIST

   /// The signed `invoice-recover` payload: `[invoice_id, btc_address]`
   /// (`recover_payload_fields`, src/invoice.rs:1815). The address is signed
   /// RAW (no trim/normalize) — the verified bytes must equal the POSTed bytes.
   /// UNLIKE invoice-list, `nym_or_empty` is the NON-EMPTY path nym.
   List<String> buildInvoiceRecoverPayloadFields({
     required String invoiceId,
     required String btcAddress,
   }) => [invoiceId, btcAddress];

   /// The signed `invoice-recovery-list` payload: ZERO fields
   /// (`recovery_list_payload_fields() == []`, server spec §3.1). Like
   /// invoice-list, the `nym_or_empty` slot is EMPTY (identity-wide). If the
   /// server ever adds a param it MUST be appended here in lockstep — the
   /// contract test pins the empty layout. (Zero-field vs a sentinel version
   /// tag is server Open Question 3; align before Phase 1 freezes the wire.)
   List<String> buildInvoiceRecoveryListPayloadFields() => const [];
   ```
2. **`lib/features/bullnym/domain/bullnym_invoice.dart`** — add DTOs:
   ```dart
   class BullnymRecoverChainSwapResponse { final String status; final String txid; }

   /// One recoverable chain swap (server `RecoverableItem`). ONE PER SWAP — an
   /// invoice with two stuck swaps yields two of these, distinguished by
   /// `lockupAddress`. `refundAddress`/`refundTxid` are the reconciliation echo.
   class BullnymRecoverableSwap {
     final String invoiceId;
     final String nym;              // build the per-nym recover URL from THIS
     final String recoveryStatus;   // 'refund_due' | 'refunding' | 'refunded'
     final int userLockAmountSat;
     final int serverLockAmountSat; // effective (renegotiation-aware)
     final String lockupAddress;    // swap identity within an invoice
     final String? refundAddress;   // committed first-write-wins destination
     final String? refundTxid;
     final int swapCreatedAtUnix;
     final int swapUpdatedAtUnix;
     // Flattened invoice context (server nested `invoice` object):
     final String invoiceStatus;
     final int invoiceAmountSat;
     final int? fiatAmountMinor;
     final String? fiatCurrency;
     final String? publicDescription;
     final String? invoiceNumber;
     final int invoiceCreatedAtUnix;
   }

   class BullnymRecoverableSwapList {
     final bool recoveryEnabled;              // server chain_swap_merchant_recovery flag
     final List<BullnymRecoverableSwap> items;
     final int count;
     final bool hasMore;                      // true → >100 rows → "contact support"
   }
   ```
   `invoice-list` (`BullnymInvoiceListItem`) is NOT modified — recovery no longer rides it.
3. **`lib/features/bullnym/domain/bullnym_client_port.dart`** — add two methods:
   ```dart
   /// Signed `invoice-recovery-list` (detection): GET /api/v1/invoices/recoverable.
   /// npub-keyed, empty nym, zero payload fields. Always available behind auth
   /// regardless of the server recover flag (`recoveryEnabled` reports the flag).
   Future<BullnymRecoverableSwapList> listRecoverableChainSwaps({
     required BullnymAuthSigner signer,
   });

   /// Signed `invoice-recover` (linked-only): POST /api/v1/:nym/invoices/:id/recover.
   /// `nym` is REQUIRED (non-null, signed into nym_or_empty), taken from the
   /// recoverable row. First-write-wins destination; idempotent retry returns the same txid.
   Future<BullnymRecoverChainSwapResponse> recoverChainSwap({
     required BullnymAuthSigner signer,
     required String nym,
     required String invoiceId,
     required String btcAddress,
   });
   ```
4. **`lib/features/bullnym/data/bullnym_http_client.dart`** — implement both:
   - `listRecoverableChainSwaps`: sign via `_signInvoiceAction(action:
     bullpayActionInvoiceRecoveryList, nymOrEmpty: '', payloadFields:
     buildInvoiceRecoveryListPayloadFields(), timestampSecs: _nowSecs())`, then
     `_getMap('/api/v1/invoices/recoverable', queryParameters: { 'npub': signer.npubHex,
     'timestamp': timestamp, 'signature': signatureHex })`. Parse with a tolerant reader
     (`_parseRecoverableListResponse`) mirroring `_parseListInvoicesResponse`: `recovery_enabled`
     via `_requiredBool`, `count`/`has_more` via `_requiredInt`/`_requiredBool`, each `items`
     entry via `_parseRecoverableItem` (flatten the nested `invoice` object; unknown keys
     ignored).
   - `recoverChainSwap`: `_signInvoiceAction(action: bullpayActionInvoiceRecover, nymOrEmpty:
     nym, payloadFields: buildInvoiceRecoverPayloadFields(...), timestampSecs: _nowSecs())`, then
     `_postMap('/api/v1/${Uri.encodeComponent(nym)}/invoices/${Uri.encodeComponent(invoiceId)}/recover',
     data: { 'npub': signer.npubHex, 'timestamp': timestamp, 'signature': signatureHex,
     'btc_address': btcAddress })`, parse `status`/`txid` with `_requiredString`. The server signs
     AND broadcasts inside this request, so allow a per-call `receiveTimeout` override (e.g. 30s)
     rather than the default 15s (`bullnymReceiveTimeout`) — a premature client timeout is the
     main source of `RecoveryInProgress` retries.
5. **`lib/features/bullnym/public/bullnym_facade.dart`** — thin delegations
   `listRecoverableChainSwaps(...)` and `recoverChainSwap(...)` next to `listInvoices`/
   `cancelInvoice` (straight `_client.*` pass-through, same as the other invoice methods that
   sign in the client).
6. **Contract tests** — append to `test/features/bullnym/bullnym_invoice_contract_test.dart`
   (append-only tripwire, same as the three existing `T-INV-SIGN` groups):
   - golden byte-layout vector for `invoice-recover`
     (`bullpay-la-v2\0invoice-recover\0<npub>\0<nym>\0<invoice_id>\0<btc_address>\0<timestamp>`);
   - golden byte-layout vector for `invoice-recovery-list` — ZERO payload fields, EMPTY nym:
     `bullpay-la-v2\0invoice-recovery-list\0<npub>\0\0<timestamp>` (the empty-nym field still
     emits its trailing NUL; then the timestamp appends with no trailing NUL). Pin
     `buildInvoiceRecoveryListPayloadFields() == const []` so a future param fails the test —
     mirrors the server's `recovery_list_payload_field_order` unit test.
   - request/response shape tests for `recoverChainSwap` and `listRecoverableChainSwaps`
     (`recovery_enabled`/`has_more`/`count`, one-row-per-swap, flattened invoice context,
     unknown-key tolerance).
7. **`integration_test/support/fake_bullnym_client.dart`** — implement
   `listRecoverableChainSwaps` returning a configurable `BullnymRecoverableSwapList`, and add
   `FakeRecoveryMode` (`available / inProgress / alreadyRecoveredSameAddress /
   alreadyRecoveredDifferentAddress / notAvailable / addressInvalid / routeAbsent404`) plus a
   `recoverEnabled` toggle for the detection flag; record `recoverCalls` for assertions,
   following the existing `FakePosMode` pattern. The existing `_toListItem`
   (`settlementStatus: 'none'`) is left untouched — recovery rides the new endpoint, not the list.

## 5. Detection

### 5.1 What "stuck" looks like on the wire

`StuckRecoveryState` mapper (in `payment_recovery/domain`, one constants file): reads each
`BullnymRecoverableSwap.recoveryStatus` — `'refund_due'` → **actionable**; `'refunding'` →
**in-flight**; `'refunded'` → **terminal-recovered**; unknown strings → **in-flight-unknown**
(visible, action disabled — a NEWER server state must not hide a stuck payment, and must not
enable a recover button either). `settlementStatus` on `invoice-list` is **not** consulted for
recovery (§2.3). `claim_stuck` (operator-side, not client-recoverable) is not returned by this
endpoint and is out of scope for v1 (Open Question 4 tracks whether to surface it separately).

### 5.2 Which invoices to watch (watch-set)

Source of truth = the dedicated signed detection endpoint
(`BullnymFacade.listRecoverableChainSwaps`), NOT any local history, NOT `invoice-list`, NOT the
public status endpoint:

- `ScanStuckPaymentsUsecase.execute()`:
  1. Resolve identity signer via `RecoveryIdentityPort` (same derivation as
     `InvoicesIdentityDatasource.getSigningHandle`,
     `lib/features/invoices/data/datasources/invoices_identity_datasource.dart` — default BTC
     wallet xprv at point of use, npub via
     `NostrIdentityFacade.deriveBullnymServerAuthPublicKeyFromXprv`). **No nym lookup is needed**:
     the endpoint is npub-wide and each row carries its own `nym` for the recover URL, and it does
     NOT require an active registration (§2.3). So — unlike the invoices flow — the scan does NOT
     call `lookupWalletOwnedRegistration`, and it still fires for a merchant whose registration
     lapsed (they may have stranded funds precisely because they stopped using the app). If no
     default Bitcoin wallet / seed is available (locked, superwallet mode) the scan is a no-op.
  2. **One request:** `listRecoverableChainSwaps(signer)`. `items` non-empty = detection. No page
     walk, no horizon window (the server returns the complete recoverable set, normally empty).
     If `has_more == true` (>100 rows), flag the whole set "contact support" (operator incident,
     spec §5.1) and still persist what came back.
  3. Reconcile the Drift repo against the returned rows (see §5.2.4). Rows are per-swap; the local
     recovery table is per-invoice (matching the recover endpoint's granularity, §7), so group
     the rows by `invoiceId` when computing per-invoice state and the badge count. Locally
     persisted non-terminal rows that no longer appear in the response are re-checked once and
     dropped to `dismissed` if genuinely gone (stale detection / recovered elsewhere).
  4. Upsert rows into the Drift repo — **adopting the server-echoed reconciliation fields**: if a
     swap row's `refundAddress`/`refundTxid` are non-null and the local invoice row has none
     (fresh install, reinstall, or another device committed first), persist them as the committed
     values and set state accordingly (`refunded` + txid → `recovered`; `refunding` →
     `recovering`; `refund_due` with a committed address → `addressCommitted`; `refund_due` with
     no address → `detected`). Never overwrite a locally committed address with a DIFFERENT echoed
     one — that mismatch is surfaced, not "fixed" (§9). Persist `recoveryEnabled` alongside for
     the UI. Emit count (distinct invoices with an actionable/in-flight swap).

### 5.3 When to scan (cadence, battery, network)

Foreground-first; the money is safe while parked (`refund_due` is non-terminal server state — no
client-side deadline), so detection latency of "next app use" is acceptable and cheap. Every scan
is now a **single** signed GET against a usually-empty endpoint:

- **Get Paid hub open / pull-to-refresh:** `GetPaidDashboardCubit.refresh()` additionally calls
  `PaymentRecoveryFacade.scan()` (fire-and-forget with generation guard, same `_isStale` pattern
  already in that cubit). Cost: 1 signed HTTPS GET.
- **App resume:** the scan piggybacks on the existing foreground resume machinery — register a
  lightweight listener alongside `SyncCoordinator`'s `AppLifecycleListener` precedent
  (`lib/core/sync/sync_coordinator.dart:52`), throttled to at most one scan per 15 minutes
  (persisted `lastScanAtUnix`).
- **While a stuck row is in-flight (`refunding`) or mid-recover:** the detail cubit re-polls the
  same `listRecoverableChainSwaps` endpoint (cheap — the whole recoverable set is one call) with
  the exact backoff of `InvoiceDetailCubit._poll` (3s → ×2 → cap 30s, generation-guarded, stop on
  terminal/dispose), keying the row of interest by `(invoiceId, lockupAddress)`. **Never** the
  public `getInvoiceStatus` — it carries no recovery state (§2.2).
- **Background: DROPPED for v1 (decided 2026-07).** No workmanager recovery scan. Detection is
  foreground-only (hub open + app resume). A detect-only BG scan (badge-warming, never signs)
  remains a possible future addition but is out of scope; recovery signing never runs in the
  background under any circumstance.
- **Push:** none — the app has no push/local-notification stack (no notification package in
  `pubspec.yaml`); see Open Question 2.

## 6. Recovery flow

**LOCKED (decided 2026-07): ONE-TAP ONLY. No automatic recovery — foreground,
merchant-initiated, single tap. Recovery always sends to the merchant's DEFAULT
Bitcoin wallet; no wallet picker and no external/cold-storage address in v1.
Recovery only ever runs on mainnet (no non-prod network knob).**

**Recover-action availability is server-driven.** The recover button is offered only when the
detection response's `recoveryEnabled == true` (the server's `chain_swap_merchant_recovery`
flag). When `false`, the stuck payment is still detected and shown read-only with a "Recovery
isn't available yet — contact support; your funds are safe on the server" message; no recover
POST is attempted. This decouples detection rollout from broadcast enablement and lets ops flip
the flag with no app release (server spec §7).

Rationale (decided): the action moves real BTC and — more importantly — creates an out-of-band
accounting obligation at the till (§8). The signature scope is narrow, the address always comes
from the merchant's own wallet, and the server is idempotent, so full-auto is *fund-safe*; but the
merchant must consciously learn "this sale did not settle normally; reconcile with the customer".

- **The one and only flow (`one-tap`):** stuck payment surfaces as banner/badge → detail screen →
  single "Recover funds to my wallet" button (shown only when `recoveryEnabled`) with a confirm
  sheet that states amount, destination (the DEFAULT Bitcoin wallet), and the out-of-band note. No
  address entry, no wallet picker, no second decision.
- **No automatic recovery.** There is no `autoRecoverStuckPayments` setting, no consent dialog for
  auto, and no scan→recover chaining. Recovery is only ever triggered by the merchant tapping the
  button in the foreground (decided 2026-07). Signing/broadcast therefore never runs in a
  background isolate.

### 6.1 `RecoverStuckPaymentUsecase.execute(invoiceId)` — exact sequence

1. Load row; require state ∈ {`detected`, `addressCommitted`, `failed`} AND
   `recoveryEnabled == true` (else abort with the "contact support" surface — no POST).
   `recovering` → no-op (single-flight guard, also a `Set<String>` in-memory lock for concurrent
   cubits). The `nym` for the recover URL is the one persisted from the recoverable row (§5.2), not
   a fresh registration lookup.
2. **Resolve destination address — commit-before-send (LOCKED):**
   - If `row.refundAddress != null` → **reuse it verbatim** (first-write-wins mirror; never
     re-derive on retry). This includes a server-echoed address adopted at scan time (§5.2.4).
   - Else derive fresh from the DEFAULT Bitcoin wallet, exactly the invoices path:
     `WalletRepository.getWallets(environment, onlyDefaults: true, onlyBitcoin: true)` →
     `WalletAddressRepository.generateNewReceiveAddress(walletId)`
     (`lib/features/invoices/application/usecases/create_invoice_usecase.dart:_freshBitcoinAddress`).
     **Persist `refundAddress` + state `addressCommitted` BEFORE any network call** — this is what
     makes every idempotent retry reuse the exact committed bytes. Then label it best-effort via
     `LabelsFacade`/`NewLabel.addr(address: ..., label: ..., origin: 'recovery:<invoiceId>')`; add
     a `recoveryLabelSystem = 'recovery'` const + `LabelSystem.recovery` case following the
     `invoiceLabelSystem` precedent just added in `lib/core/storage/tables/labels_table.dart` /
     `lib/features/labels/domain/primitive/label_system.dart`.
3. Resolve signer (`RecoveryIdentityPort.getSigningHandle()`); set state `recovering`. Use the
   `row.nym` persisted from detection.
4. `BullnymFacade.recoverChainSwap(signer: ..., nym: row.nym, invoiceId: ..., btcAddress:
   row.refundAddress)`.
5. On `{status:"recovered", txid}` → persist `refundTxid`, state `recovered`. Then re-run the
   **`listRecoverableChainSwaps` scan** once: if this invoice still has a `refund_due` swap (a
   SECOND stuck swap on the same invoice — the server recovers one swap per call and explicitly
   supports this, `src/invoice.rs:1150-1156`; it appears as a distinct
   `(invoiceId, lockupAddress)` row), flip the invoice's local row back to `detected` keeping the
   SAME `refundAddress` (per-invoice address reuse is deliberate: it keeps local state
   one-row-per-invoice and the server's per-swap first-write-wins commits succeed with the same
   address; minor address-reuse privacy cost, own wallet only).
6. On error → map (§9), persist `lastErrorCode`/`attemptCount`/`lastAttemptAtUnix`, state per §9.

## 7. Persistence (Drift)

New table `lib/core/storage/tables/payment_recoveries_table.dart`, registered in the
`@DriftDatabase(tables:[...])` list of `lib/core/storage/sqlite_database.dart` with a
`currentSchemaVersion` bump **16 → 17** (verified still 16 at the base commit) and a
`schema_16_to_17.dart` step in `lib/core/storage/migrations/` following `schema_15_to_16.dart`:

```dart
@DataClassName('PaymentRecoveryRow')
class PaymentRecoveries extends Table {
  TextColumn get invoiceId => text()();            // PK — server invoice id
  TextColumn get nym => text()();                  // path nym at detection time
  TextColumn get state => text()();                // recovery_state wire string
  TextColumn get refundAddress => text().nullable()(); // COMMITTED address (never rewritten once set)
  TextColumn get refundTxid => text().nullable()();
  TextColumn get lockupAddress => text().nullable()(); // most-recently-actionable swap identity (display/keying)
  IntColumn get amountSat => integer().nullable()();   // display-only, from the recoverable row (user_lock_amount_sat)
  TextColumn get fiatCurrency => text().nullable()();
  IntColumn get fiatAmountMinor => integer().nullable()();
  IntColumn get detectedAtUnix => integer()();
  IntColumn get lastAttemptAtUnix => integer().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastErrorCode => text().nullable()();
  BoolColumn get acknowledged => boolean().withDefault(const Constant(false))(); // merchant saw the out-of-band notice
  @override
  Set<Column> get primaryKey => {invoiceId};
}
```

`DriftPaymentRecoveryRepository` follows `DriftGetPaidSettingsRepository`'s shape (typed
exceptions wrapping Drift errors, read-modify-write). This table is what makes first-write-wins
address reuse and idempotent retry survive app restarts.

**One row per INVOICE, not per swap.** The detection endpoint returns one row per chain swap, but
the recover action is per-invoice (it recovers the currently actionable swap of an invoice and
reuses one committed address across that invoice's swaps, §6.1 step 5), so the local table stays
keyed by `invoiceId`. Per-swap detail (`lockupAddress`, per-swap amounts) is display-only; the
scan maps the swap rows down to per-invoice state. `recoveryEnabled` is a transient flag from the
last scan — keep it on the cubit/state rather than the table (it is server-global, not per-row).

**Post-reinstall reconciliation (LOCKED approach):** the table does not survive a wipe/reinstall
— by design the recovery source of truth after restore is the **server echo** on the recoverable
endpoint. The next scan (`listRecoverableChainSwaps`) returns every recovery-lifecycle swap of
the npub with its committed `refund_address` + `refund_txid` (spec §6), and §5.2.4 adopts those
into the fresh table, so a reinstalled app shows the same committed destination and never derives
a competing address for an already-committed swap. This depends on the server keeping that echo
(hard dependency — §2.3, Phase 0 checklist; server confirms it in spec §6). The recover
endpoint's `RecoveryNotAvailable`/"different address" branch (§9) remains only as the fallback for
a client that somehow skipped the scan or a scan/POST race.

## 8. UX

- **Get Paid hub (`lib/features/get_paid/ui/screens/get_paid_dashboard_screen.dart`):**
  `GetPaidDashboardCubit` gains `PaymentRecoveryFacade` (wire in
  `lib/features/get_paid/get_paid_locator.dart`) and exposes `stuckCount` in
  `GetPaidDashboardState`. Render: (a) a warning-tinted `_StatusBadge` variant on the POS
  `GetPaidSlotCard` ("1 payment needs attention" — add an optional `statusWarning` flag beside
  the existing `statusActive`, `lib/features/get_paid/ui/widgets/get_paid_slot_card.dart:18`),
  and (b) a `StuckPaymentBanner` above the slots when `stuckCount > 0`, tappable →
  `StuckPaymentsScreen` (route added in `lib/features/get_paid/ui/get_paid_router.dart`).
- **Stuck payments list screen:** rows show fiat/sat amount, detected time, state chip
  (`Needs recovery` / `Recovering…` / `Recovered` / `Failed — tap to retry`). When the last scan
  reported `recoveryEnabled == false`, or `hasMore == true` (>100 recoverable rows — operator
  incident, spec §5.1), the screen shows a read-only "contact support — your funds are safe on the
  server" banner and hides the recover button.
- **Detail screen:** the money copy. Before recovery: "The customer's Bitcoin payment for
  **CA$42.50** got stuck in transit. The funds are safe. Recover them to your Bull Bitcoin
  wallet." Primary button (only when `recoveryEnabled`) → confirm sheet: destination wallet name,
  fresh address (truncated),
  and — non-dismissable checkbox on first ever recovery — **"This sale did NOT settle at the
  register. If the customer is owed goods or a refund, settle with them in person — this app only
  recovers the coins to you."** After recovery: txid (copyable, mempool link via the existing
  mempool settings), state `Recovered`, persistent "settle with your customer" note until
  `acknowledged` is tapped.
- **No escape hatch (decided 2026-07):** recovery always targets the DEFAULT Bitcoin wallet — no
  wallet picker and no freeform/external/cold-storage address in v1 (§10). Once an address is
  committed it is shown read-only (first-write-wins, including a server-echoed one).
- **Error surfaces:** typed copy per §9 via `PaymentRecoveryException.toTranslated(context)`
  following `invoices_error.dart` + new l10n keys in `localization/app_en.arb`.

## 9. Error mapping & edge-case/idempotency matrix

`PaymentRecoveryException.fromBullnym(BullnymException)` mirrors `InvoicesException.fromBullnym`
(server error codes arrive as `BullnymException.serverRejectedRequest(code: ...)`):

| Server / condition | Client behavior | Persisted state |
|---|---|---|
| `recoveryEnabled == false` (from the scan) | Detection still works and the row is shown, but the recover button is hidden and no POST is attempted — "contact support, funds are safe" (spec §7) | `detected` (read-only) |
| `RecoveryInProgress` | Not an error: poll via `listRecoverableChainSwaps` (3s→30s backoff, §5.3) until this invoice's swap row shows `recovery_status == 'refunded'`, harvesting `refundTxid` from the echo (fall back to ONE idempotent recover retry if the echo lacks it) | `recovering` |
| Client timeout / network drop mid-POST | Address already committed locally; retry with SAME address on next tap/scan — server is idempotent or answers `RecoveryInProgress` | `addressCommitted` (attempt++) |
| Scan echoes a swap `refundAddress` ≠ locally committed address | Should be impossible (commit-before-send both sides); indicates a multi-device race or local corruption. Surface "recovered to a previously committed address — check your wallet history / contact support"; NEVER overwrite the local `refundAddress` | `failed` (`lastErrorCode = RecoveryAddressMismatch`) |
| `RecoveryNotAvailable` "already recovered (to a different address)" | Fallback branch only for a client that skipped the scan (with the spec echo, §5.2.4 adopts the committed address before any POST). Same surface as the row above | `failed` (`lastErrorCode = RecoveryAddressMismatch`) |
| `RecoveryNotAvailable` "no recoverable chain swap" | Re-run `listRecoverableChainSwaps`: if the invoice's swap shows `refunded` → recovered (race: reconciler/another device finished it; adopt echoed txid); else stale detection → `dismissed` | `recovered` or `dismissed` |
| `RecoveryAddressInvalid` | Should be impossible (own-wallet mainnet derivation); if hit, do NOT clear `refundAddress` — keep it, surface "unexpected — update app / contact support" and report via `log.severe` (no address in the log line) | `failed` |
| `InvoiceNotFound` | Ownership/nym drift (e.g. nym re-registered). Surface generic "not recoverable from this wallet" | `failed` |
| 404 / route absent (pre-deploy detection endpoint, `BullnymErrorKind.unexpectedHttpStatus`) | Fail closed: scan yields nothing (no badge). If somehow the recover POST 404s: "Recovery isn't available yet — funds are safe on the server. Try again after updating." Stuck row stays visible; retry allowed | `detected` (attempt++, `lastErrorCode = RecoveryUnavailable`) |
| Detection endpoint absent (pre-spec server) | Scan 404s → inert: no rows, no badge. No error surface | n/a |
| App offline at scan/recover time | Scan no-ops; recover surfaces the existing network error copy; retry on resume | unchanged |
| No default Bitcoin wallet / seed unavailable (locked, superwallet mode) | `noDefaultBitcoinWallet` / `signingFailed` — action disabled with explanatory copy; identity derives at point-of-use exactly like `InvoicesIdentityDatasource`, so there is no long-lived key state | `detected` |
| Multiple `refund_due` swaps per invoice | Distinct `(invoiceId, lockupAddress)` rows; loop per §6.1 step 5 — one recover call per swap, same committed address | row cycles `recovered`→`detected` |
| Duplicate trigger (double-tap, scan + tap race) | In-memory single-flight set + `recovering` state check | unchanged |
| Testnet/regtest environment (`Environment != mainnet`) | Entire feature hidden: server address validation is mainnet-only (§11 tension) | n/a |

## 10. Security

- **Address provenance:** the refund address is ONLY ever produced by
  `WalletAddressRepository.generateNewReceiveAddress` on the merchant's own wallets (default BTC
  wallet by default), or adopted from the **signed** `invoice-recovery-list` echo of an address
  this same identity previously committed. No clipboard, no deep-link, no freeform input, no
  unauthenticated server-suggested address (the echo rides the `verify_la_v2`-authenticated
  recoverable response and is only ever a value the key-holder itself signed into a prior
  `invoice-recover`). This plus the address being INSIDE the Schnorr-signed payload means a
  MITM/compromised proxy cannot redirect funds.
- **First-write-wins, mirrored locally:** persist the committed address before the first POST and
  never rewrite it. Any mismatch (echo vs local) is surfaced, never "fixed" by re-committing.
- **Key handling:** reuse the charter-H1 pattern verbatim — xprv derived from
  `SeedRepository.get(masterFingerprint)` at point of use, captured only in the
  `BullnymAuthSigner.signHashHex` closure (`InvoicesIdentityDatasource`), never stored, never
  logged. Log lines carry invoice id + npub prefix tag at most (server `npub_log_tag` precedent);
  **never** the nsec/xprv, and never the full refund address at `severe` (Sentry-bound) level.
- **Blast radius of the signed action:** `invoice-recover` signs `[invoice_id, btc_address]` with
  a timestamp — replay is idempotent-safe server-side, and the signature authorizes nothing else.
- **UI honesty:** "recovered" copy must never imply the customer was refunded.

## 11. Rollout, flags, and test plan

- **Two independent gates — decoupled by design (spec §7):**
  - *Client feature flag (mobile dark launch):* compile-time, following the
    `bullnymBaseUrlEnvironmentKey` precedent — now in
    `lib/features/bullnym/public/bullnym_config.dart` (moved from the http client at the branch
    tip): `const bool kGetPaidRecoveryEnabled = bool.fromEnvironment('GETPAID_RECOVERY_ENABLED',
    defaultValue: false);` gates locator registration of the scan hooks + hub UI so the whole
    feature ships dark until the mobile side is ready.
  - *Server recover-action flag (`chain_swap_merchant_recovery`):* NOT a client flag — the client
    reads the server's `recoveryEnabled` field per scan and drives "Recover now" vs "contact
    support" from it. Detection is server-always-on behind Schnorr auth, so merchants can SEE
    stranded funds before broadcast is enabled; ops flip the recover flag with no app release.
  - Runtime stays fail-closed regardless: a pre-deploy detection endpoint 404s → inert (no rows);
    `recoveryEnabled == false` → visible read-only row + "contact support"; a recover POST 404 →
    "not available yet". No path fabricates a recovery.
- **Unit (L0):** golden vectors (`invoice-recover` and the zero-field `invoice-recovery-list`) +
  DTO appends in `test/features/bullnym/bullnym_invoice_contract_test.dart`;
  `test/features/payment_recovery/` usecase + cubit + repository + error-mapping suites (mirror
  the `test/features/invoices/` file set), including: first-write-wins reuse across restart,
  RecoveryInProgress→recoverable-poll→recovered, echo-adoption on fresh install, echo-mismatch
  surfaces `RecoveryAddressMismatch`, empty recoverable response produces zero detections,
  `recoveryEnabled == false` keeps the row read-only.
- **Integration:** `integration_test/pos_stuck_payment_recovery_test.dart`, AUTHORED-BUT-CI-ONLY
  in the exact `pos_lifecycle_test.dart` style (fake relay + `FakeBullnymClient` + frozen
  `FakeClock` via `integration_test/support/test_locator_overrides.dart`; add the filename to the
  `skip` set in `tool/gen_all_test.dart:24` like the other lifecycle specs): provision POS → fake
  the recoverable endpoint returning one `refund_due` swap with `recoveryEnabled: true` → scan
  detects → recover round-trip → assert the fake received ONE recover call to
  `/api/v1/<nym>/invoices/<id>/recover` whose signed fields were `[invoice_id, btc_address]` and
  whose address matches a derivable default-wallet address → idempotent re-run returns same txid →
  simulate reinstall (clear table) + re-scan with the fake echoing `refund_address`/`refund_txid`
  → assert the echoed values are adopted with no second derivation and no recover POST → separate
  case with `recoveryEnabled: false` asserts detection-only (no POST, read-only banner).
- **Staged environments — MAINNET ONLY (decided 2026-07):** bullnym will NOT add a non-prod knob
  to `validate_btc_refund_address` (`src/invoice.rs:1070`). The client is verified by the
  fake-server integration suite (no real broadcast), and the ONLY real end-to-end validation is a
  **mainnet dust-value pilot**: one deliberately-failed small chain swap on the staging bullnym
  with `chain_swap_merchant_recovery=true`, recovered to an ops-controlled merchant's default
  wallet, before enabling `GETPAID_RECOVERY_ENABLED` in a store build. There is no regtest/testnet
  recovery path.
- **Server coordination:** two bullnym-side gates outside this repo — deploying the new detection
  endpoint (spec §3, always-on, unblocks Phases 2+) and enabling
  `features.chain_swap_merchant_recovery` in production (unblocks the recover button). The two are
  independent; ship the client dark (client flag off) first.

## 12. Phased milestones

**Phase 0 — Server endpoint deployed + contract pinned (BLOCKING for Phases 2+; no app code).**
The bullnym spec `bullnym/plans/chain-swap-recovery-detection-server.md` is implemented and
deployed to staging (`GET /api/v1/invoices/recoverable`, always-on), and both teams confirm in
writing: (1) the `RecoverableListResponse` shape — `recovery_enabled`, `items[]`
(`recovery_status`, `nym`, `refund_address`, `refund_txid`, `lockup_address`, amounts, invoice
context), `count`, `has_more` — exact key names pinned; (2) the echo of committed
`refund_address`/`refund_txid` on the rows is guaranteed (the mobile reinstall story depends on
it — server spec §6); (3) the `invoice-recovery-list` signed layout: **zero payload fields, empty
nym** (server Open Question 3 — confirm zero-field vs a sentinel version tag BEFORE Phase 1
freezes the golden vector); (4) the endpoint name/action final (`invoice-recovery-list` vs
`needs-recovery`, server Open Question 4). Deliverable: an appended section in
`lib/features/bullnym/bullnym_architecture.md`.
*Accept:* both repos agree on the response shape, the echo guarantee, the signed bytes, and the
endpoint/action name, in writing.

**Phase 1 — Wire + signing (client-complete, dark; can start before Phase 0 closes).**
§4 items 1–7: action constants (`invoice-recover`, `invoice-recovery-list`), payload builders
(incl. the zero-field recovery-list builder), DTOs (`BullnymRecoverableSwap[]` +
`BullnymRecoverableSwapList`, `BullnymRecoverChainSwapResponse`), port (both methods), http
client, facade, both golden vectors, fake modes. No UI. Only the final endpoint/action name and
the zero-field-vs-sentinel decision wait on Phase 0.
*Accept:* contract tests green incl. both new golden vectors and the recoverable-list round-trip
(one-row-per-swap, `recovery_enabled`, `has_more`); `FakeBullnymClient` drives all recovery modes;
`flutter analyze` clean.

**Phase 2 — Persistence + detection (visible, read-only; requires Phase 0).**
Drift table + migration (16→17), repository, `ScanStuckPaymentsUsecase` (single recoverable GET,
per-swap→per-invoice mapping, echo adoption), hub badge + banner + stuck-payments list screen (no
recover button yet — read-only, honoring `recoveryEnabled`/`hasMore`), scan on hub open/app resume
with throttle.
*Accept:* a fake-backed integration run shows a `refund_due` recoverable row producing a persisted
`detected` row and a hub badge across an app restart; an empty recoverable response produces zero
detections; the scan issues exactly ONE signed GET; echoed address/txid are adopted on a cleared
table; a scan runs even with no active registration (identity signer only).

**Phase 3 — Manual one-tap recovery (SHIPPABLE MVP).**
`RecoverStuckPaymentUsecase` with commit-before-send and `recoveryEnabled` gating, detail screen +
confirm sheet + first-time out-of-band disclosure, full §9 error matrix, address labeling
(`LabelSystem.recovery`), recoverable-endpoint `refunding` polling, multi-swap loop, l10n. Client
flag still default-off.
*Accept:* integration test drives detect → one-tap → recovered (txid persisted) → idempotent
retry; timeout/RecoveryInProgress/echo-mismatch/`recoveryEnabled==false`/404 branches each land in
the specified persisted state; committed address is byte-identical across retries and app
restarts; recover POST targets `/api/v1/<row.nym>/invoices/<id>/recover`.

**Phase 4 — REMOVED (decided 2026-07).**
No automatic recovery and no background signing: recovery is one-tap, foreground, manual only, so
the `autoRecoverStuckPayments` setting, its consent dialog, and scan→recover chaining are all
dropped. An optional detect-only `BackgroundTask.getPaidRecoveryScan` (badge-warming, never signs)
is DEFERRED and out of v1 — foreground detection (hub open + app resume, §5.3) is the v1 surface.
The feature ends at Phase 3.

**Phase 5 — Rollout.**
Staging pilot per §11, enable `GETPAID_RECOVERY_ENABLED` in internal builds, then store release;
the server `chain_swap_merchant_recovery` flip is independent (drives `recoveryEnabled`).
*Accept:* one real recovered mainnet payment on staging with txid confirmed to the merchant
wallet; support runbook written.

## 13. Open questions / cross-team dependencies

Resolved since the prior draft (now baked in above, not open): the detection transport (dedicated
signed `GET /api/v1/invoices/recoverable`, `invoice-recovery-list`, NOT `invoice-list` — server
spec §2/§3, §2.3 here); **multi-swap representation** (one row per swap keyed
`(invoiceId, lockupAddress)` — was OQ1); **scan/poll ergonomics** (the dedicated endpoint IS the
answer — one cheap usually-empty GET, no page-walk — was OQ2); detection auth (signed only, never
the public status endpoint, §2.2); the recoverable population (nym-linked checkout invoices only,
§2.1); consent default (one-tap, full-auto opt-in, §6); recover-action availability (server-driven
via `recoveryEnabled`, detection always-on, §6/§11); address policy (fresh default-BTC derivation
persisted before first POST, §6.1); and post-reinstall reconciliation (server echo on the
recoverable rows, §7).

RESOLVED 2026-07 (baked in above):
- ~~BG-isolate signing for auto-recovery~~ → **foreground only; no auto-recovery at all** (§6, Phase 4 removed).
- ~~non-prod `validate_btc_refund_address` knob~~ → **no; mainnet only** (§11).
- ~~freeform/external/cold-storage recovery address~~ → **no; default wallet only** (§6, §8, §10).

Still open:
1. Do we want local push notifications ("a payment needs attention") — currently NO notification
   package exists in the app — or is the hub badge + foreground resume scan sufficient for v1?
   (Leaning sufficient: funds are safe while parked.)
2. Should `claim_stuck` invoices (operator-side stuck claims, not client-recoverable) surface in
   the same "needs attention" list as read-only rows, or stay hidden? (Not returned by the
   recoverable endpoint, so this would need a separate signal.)

**Pending server sign-off (align before Phase 1 freezes the wire):** the endpoint name/action
(`invoice-recovery-list` vs `needs-recovery` — server OQ4) and the **zero-field vs sentinel signed
payload** (server OQ3). Both must be settled before the `invoice-recovery-list` golden vector is
committed. Also nice-to-have but not required: whether `InvoiceListItem` later carries a compact
`recovery_status` hint for the invoice-detail screen (server OQ5 — the client keys the recoverable
response by `invoice_id` instead and does not need it).
