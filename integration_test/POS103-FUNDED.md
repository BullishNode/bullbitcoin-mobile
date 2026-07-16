# Funded POS-103 run (S-REAL-PROD-POS103-FUNDED)

`integration_test/get_paid_pos103_funded_test.dart` drives one authorized,
end-to-end funded journey for the Get Paid **Point of Sale** product (BIP85
wallet-seed index **103**, a Liquid wallet) against **production** Bullnym +
Nostr + the live Liquid network. It is the POS sibling of the Page-102 witness
(`get_paid_page102_funded_test.dart`, `FUNDED-RUN.md`) — same machinery, wallet
index 103 instead of 102 — with one added, load-bearing property:
**destination isolation**.

**This lane moves real funds.** The spec never pays anything itself: it
publishes the payable addresses to a handshake directory, waits for an
**external coordinator** to fund wallet 103, observes the receipt and the
autosweep through the app's own wallet sync, then returns the balance via the
app's real Liquid Send flow to an address the coordinator writes back. Every
phase prints a machine-readable `CHECKPOINT` line so the coordinator can journal
the run.

It is excluded from the default aggregate run (`tools/gen_all_test.dart` skip
set) and driven only by the coordinator's `scenarios/pos103` Linux lane.

## Destination isolation — the invariant under test

POS and the Lightning Address share **one nym** but must never share a
settlement destination. A POS sale settles to the dedicated POS wallet **103**
and NEVER to the Lightning Address wallet **101**
(`provision_pos_usecase.dart`: "POS sales settle to 103, never 101/102"; KR-1
descriptor guard). This witness proves that on two independent channels:

- **App-observed** (this spec): it registers the shared Lightning Address first
  (which materializes wallet 101), baselines wallet 101's balance, then after
  the payment asserts wallet 103 received the funds AND wallet 101 is unchanged.
  A leak into wallet 101 fails the run at `isolation_asserted`, before any sweep
  or return.
- **On-chain** (coordinator's independent oracle): the request publishes the
  wallet-101 receive address, and the oracle runs `expectNoTx` against it —
  proving no transaction ever touched wallet 101 on the chain itself.

## Journey (checkpoint steps)

| step | meaning |
|------|---------|
| `env_check` | fixtures resolved (lane guard, mnemonic, handshake dir all present) |
| `wallet_restored` | default wallets recreated from `GETPAID_FUNDED_MNEMONIC` |
| `lightning_registered` | wallet-owned Lightning Address nym registered (POS reuses it; materializes wallet 101) |
| `wallet101_resolved` | Lightning Address wallet 101 resolved (the isolation guard's subject) |
| `pos_provisioned` | POS terminal provisioned; wallet 103 (Liquid) materialized, autosweep on |
| `addresses_derived` | wallet-103 + wallet-101 + default-Liquid receive addresses derived |
| `handshake_offer_written` | `pos103_request.json` published; now awaiting payment |
| `awaiting_payment` | polling wallet-103 sync (status `waiting` / `timeout`) |
| `payment_detected` | wallet-103 balance reached the target amount |
| `receipt_asserted` | app wallet state reflects the receipt on wallet 103 |
| `isolation_asserted` | wallet 101 balance UNCHANGED from baseline — POS funds never touched the LA wallet |
| `autosweep_swept` | autosweep fired on sync; sweep txid captured |
| `awaiting_sweep_drain` / `awaiting_sweep_credit` | polling 103 drain + default-Liquid credit |
| `sweep_asserted` | wallet 103 drained; default Liquid wallet credited |
| `awaiting_return_address` | polling `pos103_response.json` for `return_address` |
| `return_address_read` | coordinator's return address read |
| `return_prepared` | drain PSET built; absolute fee computed and asserted `<= max_fee_sat` |
| `return_broadcast` | real Liquid Send broadcast; return txid captured |
| `result_written` | `pos103_result.json` published |
| `done` | terminal success |

Checkpoint line format (single line, stdout):

```
CHECKPOINT {"step":"isolation_asserted","status":"ok","ts":"2026-07-16T...Z","wallet101_balance_before_sat":"0","wallet101_balance_after_sat":"0","pos103_balance_sat":"2000"}
```

`status` is `ok` for milestones, `waiting`/`timeout` for polls. Only non-secret
values are ever emitted (addresses, txids, amounts, balances, run id, nym) —
**never the mnemonic or any signer material.** Balances are strings because they
are `BigInt` satoshis.

## Environment variables

Identical to the Page-102 witness (the coordinator reuses one `GETPAID_FUNDED_*`
contract across the funded witnesses); only the lane guard value differs.

| var | required | default | meaning |
|-----|----------|---------|---------|
| `GETPAID_E2E_LANE` | yes | — | must equal `S-REAL-PROD-POS103-FUNDED` |
| `GETPAID_FUNDED_MNEMONIC` | yes | — | QA funded wallet mnemonic (operator-supplied at run time; never logged) |
| `GETPAID_FUNDED_HANDSHAKE_DIR` | yes | — | existing writable directory for the handshake files |
| `GETPAID_FUNDED_NYM` | no | `bbe2epos103<runId>` | nym to register / reuse (sanitized to `[a-z0-9]`) |
| `GETPAID_FUNDED_RUN_ID` | no | epoch ms in base36 | run correlation id |
| `GETPAID_FUNDED_AMOUNT_SAT` | no | `2000` | amount wallet 103 must receive (direct Liquid; see note below) |
| `GETPAID_FUNDED_MAX_FEE_SAT` | no | `10000` | ceiling asserted on the return-send absolute fee |
| `GETPAID_FUNDED_FEE_RATE` | no | `0.1` | Liquid fee rate (sat/vB) for the return drain |
| `GETPAID_FUNDED_PAYMENT_TIMEOUT_SEC` | no | `900` | max wait for the payment / sweep to settle |
| `GETPAID_FUNDED_RETURN_TIMEOUT_SEC` | no | `900` | max wait for the coordinator's return address |
| `GETPAID_FUNDED_POLL_INTERVAL_SEC` | no | `15` | poll interval for all waits |

All variables are read from the process environment, with `--dart-define`
fallbacks for `GETPAID_E2E_LANE`, `GETPAID_FUNDED_NYM`, `GETPAID_FUNDED_RUN_ID`,
and `GETPAID_FUNDED_HANDSHAKE_DIR`.

### Why 2,000 sats (dust-margin rationale, direct-Liquid witness)

The POS wallet 103 is a Liquid wallet, and the payer funds it by a **direct
Liquid send**, so the Boltz chain-swap 25,000-sat minimum does **not** apply —
that minimum binds only on the later BTC-rail witness. The amount is the minimum
practical value for the three-Liquid-hop journey (funding onto 103, autosweep
drain 103 → default wallet, return drain default → coordinator), identical to the
Page-102 rationale. Verified against f6eec5127: autosweep dust floor
`RunAutoSweepUsecase._dustThresholdSat = 100` sats; both app-driven hops pay the
min-relay `0.1` sat/vByte rate; a 1-in/2-out confidential Liquid tx costs roughly
100-150 sats. From 2,000 sats the final-hop output stays ~17x the dust floor.
Lower the amount only after re-checking these numbers.

Fail-fast refusal: if `GETPAID_FUNDED_HANDSHAKE_DIR` is unset (or missing on
disk), fixtures construction throws before any wallet or network work — a funded
journey with no channel back to the coordinator must not run.

## Handshake contract

All files live in `GETPAID_FUNDED_HANDSHAKE_DIR`. The spec writes with an atomic
temp-file + rename so the coordinator never sees a half-written document.

### 1. `pos103_request.json` — spec → coordinator (written at `handshake_offer_written`)

```json
{
  "schema": "getpaid-pos103-funded/v1",
  "run_id": "abc123",
  "nym": "bbe2epos103abc123",
  "network": "liquid-mainnet",
  "terminal_url": "https://.../<nym>",
  "pos103_receive_address": "lq1...",
  "lightning_address_receive_address": "lq1...",
  "default_liquid_address": "lq1...",
  "target_amount_sat": 2000,
  "max_fee_sat": 10000,
  "status": "awaiting_payment",
  "written_at": "2026-07-16T00:00:00.000Z"
}
```

The coordinator funds `pos103_receive_address` with a **direct Liquid send** so
that wallet 103 receives at least `target_amount_sat`. It uses
`lightning_address_receive_address` only to assert (via the independent oracle)
that **no** transaction ever touched wallet 101.

### 2. `pos103_response.json` — coordinator → spec (polled from `awaiting_return_address`)

Only `return_address` is required; `payment_txid` is optional (coordinator's
journal only — the spec does not depend on it).

```json
{
  "return_address": "lq1...",
  "payment_txid": "<optional liquid txid of the funding payment>"
}
```

### 3. `pos103_result.json` — spec → coordinator (written at `result_written`)

```json
{
  "schema": "getpaid-pos103-funded-result/v1",
  "run_id": "abc123",
  "nym": "bbe2epos103abc123",
  "network": "liquid-mainnet",
  "autosweep_txid": "<liquid txid>",
  "return_txid": "<liquid txid>",
  "return_address": "lq1...",
  "return_fee_sat": 34,
  "final_pos103_balance_sat": "0",
  "final_default_liquid_balance_sat": "0",
  "final_lightning_address_balance_sat": "0",
  "status": "complete",
  "written_at": "2026-07-16T00:10:00.000Z"
}
```

## Launch command

```bash
export GETPAID_E2E_LANE=S-REAL-PROD-POS103-FUNDED
export GETPAID_FUNDED_MNEMONIC="<funded QA mnemonic>"   # operator-supplied; never commit/log
export GETPAID_FUNDED_HANDSHAKE_DIR="$HS"
# optional overrides: GETPAID_FUNDED_AMOUNT_SAT, GETPAID_FUNDED_MAX_FEE_SAT,
# GETPAID_FUNDED_NYM, GETPAID_FUNDED_RUN_ID, GETPAID_FUNDED_*_TIMEOUT_SEC ...

fvm flutter test integration_test/get_paid_pos103_funded_test.dart \
  -d linux --reporter=expanded
```

The spec's overall `flutter_test` timeout is 45 minutes; the payment and return
waits are bounded by the `*_TIMEOUT_SEC` variables above. Normally this spec is
launched by the coordinator's `scenarios/pos103` Linux lane, not by hand — see
`getpaid-e2e` `docs/POS103-RUNBOOK.md`.
