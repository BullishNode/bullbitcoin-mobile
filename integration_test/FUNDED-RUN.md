# Funded Page-102 run (S-REAL-PROD-PAGE102-FUNDED)

`integration_test/get_paid_page102_funded_test.dart` drives one authorized,
end-to-end funded journey for the Get Paid **Payment Page** product (BIP85
wallet-seed index **102**, a Liquid wallet) against **production** Bullnym +
Nostr + the live Liquid network.

**This lane moves real funds.** The spec never pays anything itself: it publishes
the payable addresses to a handshake directory, waits for an **external
coordinator** to fund wallet 102, observes the receipt and the autosweep through
the app's own wallet sync, then returns the balance via the app's real Liquid
Send flow to an address the coordinator writes back. Every phase prints a
machine-readable `CHECKPOINT` line so the coordinator can journal the run.

It is excluded from the default aggregate run (`tools/gen_all_test.dart` skip
set) and has its own make lane.

## Journey (checkpoint steps)

| step | meaning |
|------|---------|
| `env_check` | fixtures resolved (lane guard, mnemonic, handshake dir all present) |
| `wallet_restored` | default wallets recreated from `GETPAID_FUNDED_MNEMONIC` |
| `lightning_registered` | wallet-owned Lightning Address nym registered (page save reuses it) |
| `page_created` | Payment Page saved; wallet 102 (Liquid) provisioned, autosweep on |
| `addresses_derived` | wallet-102 receive address + default-Liquid next address derived |
| `handshake_offer_written` | `page102_request.json` published; now awaiting payment |
| `awaiting_payment` | polling wallet-102 sync (status `waiting` / `timeout`) |
| `payment_detected` | wallet-102 balance reached the target amount |
| `receipt_asserted` | app wallet state reflects the receipt on wallet 102 |
| `autosweep_swept` | autosweep fired on sync; sweep txid captured |
| `awaiting_sweep_drain` / `awaiting_sweep_credit` | polling 102 drain + default-Liquid credit |
| `sweep_asserted` | wallet 102 drained; default Liquid wallet credited |
| `awaiting_return_address` | polling `page102_response.json` for `return_address` |
| `return_address_read` | coordinator's return address read |
| `return_prepared` | drain PSET built; absolute fee computed and asserted `<= max_fee_sat` |
| `return_broadcast` | real Liquid Send broadcast; return txid captured |
| `result_written` | `page102_result.json` published |
| `done` | terminal success |

Checkpoint line format (single line, stdout):

```
CHECKPOINT {"step":"payment_detected","status":"ok","ts":"2026-07-16T...Z","page102_balance_sat":"2000"}
```

`status` is `ok` for milestones, `waiting`/`timeout` for polls. Only non-secret
values are ever emitted (addresses, txids, amounts, balances, run id, nym) —
**never the mnemonic or any signer material.** Balances are strings because they
are `BigInt` satoshis.

## Environment variables

| var | required | default | meaning |
|-----|----------|---------|---------|
| `GETPAID_E2E_LANE` | yes | — | must equal `S-REAL-PROD-PAGE102-FUNDED` |
| `GETPAID_FUNDED_MNEMONIC` | yes | — | QA funded wallet mnemonic (operator-supplied at run time; never logged) |
| `GETPAID_FUNDED_HANDSHAKE_DIR` | yes | — | existing writable directory for the handshake files |
| `GETPAID_FUNDED_NYM` | no | `bbe2epage102<runId>` | nym to register / reuse (sanitized to `[a-z0-9]`) |
| `GETPAID_FUNDED_RUN_ID` | no | epoch ms in base36 | run correlation id |
| `GETPAID_FUNDED_AMOUNT_SAT` | no | `2000` | amount wallet 102 must receive (direct Liquid; see note below) |
| `GETPAID_FUNDED_MAX_FEE_SAT` | no | `10000` | ceiling asserted on the return-send absolute fee |
| `GETPAID_FUNDED_FEE_RATE` | no | `0.1` | Liquid fee rate (sat/vB) for the return drain |
| `GETPAID_FUNDED_PAYMENT_TIMEOUT_SEC` | no | `900` | max wait for the payment / sweep to settle |
| `GETPAID_FUNDED_RETURN_TIMEOUT_SEC` | no | `900` | max wait for the coordinator's return address |
| `GETPAID_FUNDED_POLL_INTERVAL_SEC` | no | `15` | poll interval for all waits |

All variables are read from the process environment, with `--dart-define`
fallbacks for `GETPAID_E2E_LANE`, `GETPAID_FUNDED_NYM`, `GETPAID_FUNDED_RUN_ID`,
and `GETPAID_FUNDED_HANDSHAKE_DIR`.

### Why 2,000 sats (dust-margin rationale, direct-Liquid witness)

This first witness funds wallet 102 by a **direct Liquid send**, so the Boltz
chain-swap 25,000-sat minimum does **not** apply — that minimum binds only on
the later BTC-rail witness (which will need a scenario-cap bump). Here the amount
is the minimum practical value for the three-Liquid-hop journey: the funding
payment onto wallet 102, the autosweep drain 102 → default Liquid wallet, and the
return drain default → the coordinator. Verified against f6eec5127:

- autosweep dust floor: `RunAutoSweepUsecase._dustThresholdSat = 100` sats;
- both app-driven hops pay the min-relay rate `0.1` sat/vByte
  (`RunAutoSweepUsecase` uses `NetworkFee.relativeFromSatPerVbyte(0.1)`; this
  spec's return send defaults to the same via `GETPAID_FUNDED_FEE_RATE`), and on
  Liquid economic == min-relay because blocks are typically empty
  (`fees_repository_impl`);
- a 1-in/2-out confidential Liquid tx at that rate costs roughly 100-150 sats.

Starting from 2,000 sats: hop 2 leaves ~1,850 on the default wallet, hop 3 sends
~1,700 back — the final-hop output is ~17x the 100-sat dust floor, comfortably
above the ≥3x margin we want, without probing dust-edge behaviour. Even at a
pessimistic ~500 sats/hop the final output stays ~1,000 sats (10x). Lower the
amount only after re-checking these numbers; the default is deliberately the
smallest round value that keeps every hop clear of the dust edge.

Fail-fast refusal: if `GETPAID_FUNDED_HANDSHAKE_DIR` is unset (or missing on
disk), fixtures construction throws before any wallet or network work — a funded
journey with no channel back to the coordinator must not run. This refusal is
the compile/boot smoke's runtime proof.

## Handshake contract

All files live in `GETPAID_FUNDED_HANDSHAKE_DIR`. The spec writes with an atomic
temp-file + rename so the coordinator never sees a half-written document.

### 1. `page102_request.json` — spec → coordinator (written at `handshake_offer_written`)

```json
{
  "schema": "getpaid-page102-funded/v1",
  "run_id": "abc123",
  "nym": "bbe2epage102abc123",
  "network": "liquid-mainnet",
  "page_public_url": "https://.../<nym>",
  "page102_receive_address": "lq1...",
  "default_liquid_address": "lq1...",
  "target_amount_sat": 2000,
  "max_fee_sat": 10000,
  "status": "awaiting_payment",
  "written_at": "2026-07-16T00:00:00.000Z"
}
```

The coordinator funds `page102_receive_address` with a **direct Liquid send** so
that wallet 102 receives at least `target_amount_sat`. The spec waits for the
wallet-102 balance to reach `target_amount_sat`. (This first witness is
deliberately direct Liquid — no Boltz chain swap — which is why the small 2,000-sat
amount is usable.)

### 2. `page102_response.json` — coordinator → spec (polled from `awaiting_return_address`)

The coordinator writes this once it is ready to receive the funds back. Only
`return_address` is required; `payment_txid` is optional (for the coordinator's
own journal — the spec does not depend on it).

```json
{
  "return_address": "lq1...",
  "payment_txid": "<optional liquid txid of the funding payment>"
}
```

`return_address` must be a Liquid address the coordinator controls. The spec
drains the **entire** default Liquid wallet balance (minus fee) to it.

### 3. `page102_result.json` — spec → coordinator (written at `result_written`)

```json
{
  "schema": "getpaid-page102-funded-result/v1",
  "run_id": "abc123",
  "nym": "bbe2epage102abc123",
  "network": "liquid-mainnet",
  "autosweep_txid": "<liquid txid>",
  "return_txid": "<liquid txid>",
  "return_address": "lq1...",
  "return_fee_sat": 34,
  "final_page102_balance_sat": "0",
  "final_default_liquid_balance_sat": "0",
  "status": "complete",
  "written_at": "2026-07-16T00:10:00.000Z"
}
```

## How the coordinator drives it

1. Create an empty handshake directory `HS=<dir>`.
2. Launch the spec (see command below) with the funded mnemonic in the
   environment. Tail its stdout for `CHECKPOINT` lines.
3. Wait for `page102_request.json`. Fund `page102_receive_address` with a direct
   Liquid send so that wallet 102 receives at least `target_amount_sat`.
4. The spec detects the receipt, runs autosweep, and drains wallet 102 into the
   default Liquid wallet (checkpoints `payment_detected` … `sweep_asserted`).
5. When ready, write `page102_response.json` with a `return_address` you control.
6. The spec drains the default Liquid wallet back to `return_address`
   (`return_broadcast`) and writes `page102_result.json` (`result_written` →
   `done`).

### Launch command

```bash
export GETPAID_E2E_LANE=S-REAL-PROD-PAGE102-FUNDED
export GETPAID_FUNDED_MNEMONIC="<funded QA mnemonic>"   # operator-supplied; never commit/log
export GETPAID_FUNDED_HANDSHAKE_DIR="$HS"
# optional overrides: GETPAID_FUNDED_AMOUNT_SAT, GETPAID_FUNDED_MAX_FEE_SAT,
# GETPAID_FUNDED_NYM, GETPAID_FUNDED_RUN_ID, GETPAID_FUNDED_*_TIMEOUT_SEC ...

fvm flutter test integration_test/get_paid_page102_funded_test.dart \
  -d linux --reporter=expanded
```

Or via the make lane (defaults `INTEGRATION_DEVICE=linux`):

```bash
make page102-funded-test
```

The spec's overall `flutter_test` timeout is 45 minutes; the payment and return
waits are bounded by the `*_TIMEOUT_SEC` variables above.
