# Client PRs: Stuck-Swap Recovery — stacked-branch landing plan

Status: PLAN (2026-07-11). Server side is DONE — detection endpoint merged to
bullnym `main` (`a4cf3ab`, PR #89) and deployed to pay2; recovery action
(`invoice-recover`) validated end-to-end on mainnet (CRECV-10, refund confirmed
in block 957585). This plan lands the mobile client.

## 1. Ground truth (verified 2026-07-11)

### The stack
The Get Paid work is a stacked series on the BullishNode fork, each PR based
on its predecessor branch:

```
pr00 … pr27-invoices → pr28-getpaid-hub (#58) → pr29-getpaid-wallet-controls (#60)
                                              → pr30-getpaid-sweep-labels (#61)   ← stack tip
```

- **The pr29 and pr30 slots are TAKEN** (wallet-controls, sweep-labels).
  Our local branch `pr29-getpaid-stuck-swap-recovery` is misnamed.
- The recovery work slots in as **pr31** (and **pr32**, see §3).

### The local branch is stale; the work is uncommitted
- Local `pr29-getpaid-stuck-swap-recovery` is `ahead 21 / behind 25` of
  `origin/pr28-getpaid-hub`. The 21 "ahead" commits are **pre-rebase
  duplicates of pr26–pr28 commits** (same messages, different hashes) — worth
  nothing; do NOT rebase or cherry-pick them.
- **All recovery work is uncommitted**: 28 modified files (+1475/−22) plus 8
  untracked paths (`lib/features/payment_recovery/`,
  `payment_recoveries_table.dart`, `schema_16_to_17.dart`,
  `drift_schema_v17.json`, `schema_v17.dart`,
  `integration_test/pos_stuck_payment_recovery_test.dart`,
  `test/features/payment_recovery/`, `plans/`).

### Schema slot
Stack tip (pr30) has max Drift schema **v16** / migration `to_16`; pr29/pr30
add no schema bump and do not touch `payment_recovery`,
`wallet_address_repository`, `sqlite_database*`, or `migrations/`. Our
**16→17** bump is still valid on the tip, but the generated artifacts
(`drift_schema_v17.json`, `sqlite_database.steps.dart`, `schema_v17.dart`)
must be **regenerated on the new base**, not ported.

### Locked product decisions (do not relitigate)
Mainnet only · auto-detection foreground only · one-tap recovery only ·
recover to the merchant's **default** Bitcoin wallet (no picker) · never send
directly to cold storage.

## 2. Phase 0 — checkpoint and branch hygiene (safety first)

```bash
cd ~/bull-bitcoin-workspace/bullbitcoin-mobile          # on pr29-getpaid-stuck-swap-recovery
git add -A ':!tmp'                                       # everything except tmp/
git commit -m "WIP checkpoint: stuck-swap recovery (pre-restack)"
git branch -m pr29-getpaid-stuck-swap-recovery checkpoint/stuck-swap-recovery-wip
```

The checkpoint commit (call it `$WIP`) is the single source for the port. Its
diff base is the OLD pr28 head: `OLD_BASE=$(git merge-base $WIP origin/pr28-getpaid-hub)`.
Never delete this branch until pr32 is merged.

## 3. Two PRs, not one

Respecting the stack's "one reviewable concern per PR" convention:

| PR | Branch | Base | Content |
|---|---|---|---|
| **pr31** | `pr31-getpaid-gap-limit-guardrails` | `pr30-getpaid-sweep-labels` | Phase G of `plans/gap-limit-guardrails.md` — NEW code, not in the WIP |
| **pr32** | `pr32-getpaid-stuck-swap-recovery` | `pr31-getpaid-gap-limit-guardrails` | The recovery feature, ported from `$WIP` |

Rationale: the gap-limit fix is a hard safety blocker for recovery (recovery
reserves fresh BTC addresses; the unbounded skip loop in
`wallet_address_repository.dart:126-141` can push funds past the external gap
limit 20 where seed restore misses them), but it is independently valuable and
reviewable. Recovery stacks on it so pr32 can rely on `GapPolicy`.

## 4. Phase 1 — pr31: gap-limit guardrails (implement, new code)

Base off the tip and implement `plans/gap-limit-guardrails.md` Phase G:

```bash
git switch -c pr31-getpaid-gap-limit-guardrails origin/pr30-getpaid-sweep-labels
```

- **G1**: `GapPolicy { strict, bestEffortReuse }` + bounded window check in
  `wallet_address_repository.dart`; replace the unbounded
  `while (labels.any(isSystemLabel)) { index++; }` skip loop; add
  `GAP_HARD_BOUND = 15` (below BDK stopGap 20).
- **G2**: recovery address reservations use `bestEffortReuse` — re-serve a
  previously reserved-but-unfunded recovery address instead of burning a new
  index.
- **G3**: unit tests — window exhaustion, reuse, strict-mode failure, bound
  respected under repeated reservation.
- **G4**: doc note in the wallet architecture md.

Commit granularity: `feat(wallet): …` policy + repository change, then
`test(wallet): …`. Open PR #NN "pr31: Wallet gap-limit guardrails
(GapPolicy + bounded system-label skip)" with base `pr30-getpaid-sweep-labels`.

## 5. Phase 2 — pr32: port the recovery feature

```bash
git switch -c pr32-getpaid-stuck-swap-recovery pr31-getpaid-gap-limit-guardrails
```

### 5a. Three-way port (NOT checkout-overwrite)
For each recovery path, apply the WIP diff with 3-way merge so tip-side
changes surface as conflicts instead of being clobbered:

```bash
git diff $OLD_BASE $WIP -- <paths> | git apply -3
```

Port in dependency order, one reviewable commit per hexagon layer (matching
stack convention):
1. `feat(bullnym): recovery actions + signed endpoints` —
   `bullnym_http_client.dart`, `bullnym_client_port.dart`,
   `bullnym_invoice*.dart`, `bullnym_facade.dart`
2. `feat(storage): payment_recoveries table + schema v17` — table file +
   `sqlite_database.dart` + migration `schema_16_to_17.dart`
   (**regenerate** `sqlite_database.steps.dart`, `drift_schema_v17.json`,
   `schema_v17.dart` with build_runner/drift tools on THIS base — do not port
   generated files)
3. `feat(payment-recovery): domain + data + usecases` —
   `lib/features/payment_recovery/` (detect, `RecoverStuckPaymentUsecase`
   wired to GapPolicy.bestEffortReuse from pr31)
4. `feat(payment-recovery): cubits + UI + routes` — dashboard surfaces,
   `locator.dart`, `router.dart`, `app_en.arb`
5. `test(payment-recovery): unit + migration + integration` — including
   `wipe_app_state.dart` (`db.delete(db.paymentRecoveries)`) and
   `fake_bullnym_client.dart`

### 5b. Known conflict hotspots (base moved 25 commits + pr29 + pr30)
- `get_paid_dashboard_{cubit,state,screen}.dart` — pr28 reworked dashboard
  icons/settings entries; pr29 added wallet controls. Re-express the recovery
  banner/tile on the new dashboard, don't force the old diff.
- `locator.dart`, `router.dart`, `app_en.arb`, `pubspec.*` — trivial but
  guaranteed conflicts; re-apply by hand if `apply -3` is noisy.
- `bullnym_*` files — pr28 gained "honest validation / standard loading"
  invoice fixes; keep both.
- `get_paid_locator.dart` / settings screen — pr28 migrated settings to
  bull_ui; recovery settings entry must use the bull_ui idiom.

### 5c. Wire-contract check (against deployed pay2 `main`)
- Detection: `GET /api/v1/invoices/recoverable` signed as action
  `invoice-recovery-list`, **empty nym, ZERO fields** (bullpay-la-v2, no
  trailing NUL). Expect 400 on missing query, 401 bad sig, 200 envelope with
  `recovery_enabled`, `items[]`, `has_more`.
- Recovery: `invoice-recover` with fields `[invoice_id, btc_address]`.
  `"status":"recovered"` means **broadcast, not confirmed** — UI copy must say
  "refund sent" not "refund received".
- Server gate: recovery **action** requires
  `features.chain_swap_merchant_recovery` on the server (pay2: enabled).
  Detection is always on and echoes the flag as `recovery_enabled` — the
  client must hide/disable the one-tap button when `recovery_enabled=false`.

## 6. Phase 3 — validation gates (in order)

1. `flutter analyze` clean on pr31 and pr32.
2. Unit tests: `payment_recovery`, bullnym contract test, dashboard cubit,
   migration tests (16→17 path from a seeded v16 db).
3. Headless integration: `integration_test/pos_stuck_payment_recovery_test.dart`.
4. Manual device run against pay2 replaying CRECV-10: underpay a POS invoice →
   foreground detection shows the stuck payment → one-tap → refund lands in
   the default BTC wallet. Verify gap-window telemetry (pr31) during the run.

## 7. Stack maintenance rules

- Rebase order when a lower branch moves: pr28 → pr29 → pr30 → pr31 → pr32,
  each with `git rebase --onto origin/<new-base> <old-base>`; push with
  `--force-with-lease`.
- PR titles follow the stack convention: "pr31: …", "pr32: …"; each PR's base
  is its predecessor **branch**, never `main`.
- After a predecessor merges, retarget the PR base in GitHub before rebasing.
- Regenerated Drift artifacts are re-run after every rebase that crosses a
  schema-touching commit (cheap insurance: always re-run build_runner after
  rebase, commit only if changed).

## 8. Out of scope (explicitly)

- recovery-v2 ("server settles, phone supervises", `bullnym/plans/recovery-v2.md`)
  — not implemented server-side; the client ships against v1 semantics.
- Background/push detection — foreground only, per locked decision.
- Any wallet-picker or cold-storage destination UI.
