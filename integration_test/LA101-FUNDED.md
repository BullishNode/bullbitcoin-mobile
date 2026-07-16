# Funded LA-101 run (S-REAL-PROD-LA101-FUNDED)

`integration_test/get_paid_la101_funded_test.dart` drives one authorized,
end-to-end funded journey for the Get Paid **Lightning Address** product (BIP85
wallet-seed index **101**, a Liquid wallet) against **production** Bullnym +
Nostr + the live Liquid network. It is the Lightning-Address sibling of the
Page-102 witness (`get_paid_page102_funded_test.dart`, `FUNDED-RUN.md`) — same
machinery — with one load-bearing difference: the receive is over **Lightning**,
via a Boltz **reverse swap**, not a direct Liquid send.

**This lane moves real funds.** The spec never pays anything itself: it registers
a wallet-owned Lightning Address (materializing wallet 101), publishes the
Lightning Address + payable addresses to a handshake directory, waits for an
**external coordinator** to pay the Lightning Address over Lightning, observes the
receipt and the autosweep through the app's own wallet sync, then returns the
balance via the app's real Liquid Send flow to an address the coordinator writes
back. Every phase prints a machine-readable `CHECKPOINT` line so the coordinator
can journal the run.

It is excluded from the default aggregate run (`tools/gen_all_test.dart` skip set)
and driven only by the coordinator's `scenarios/la101` Linux lane
(`getpaid-e2e` repo, `scenarios/la101/LA101-RUNBOOK.md`).

## Routing — reverse swap, not a chain swap (why 2,000 sats)

A LN payment to a Bull Lightning Address settles L-BTC into wallet 101 via a Boltz
**REVERSE submarine swap** (bullnym source `lightning_boltz_reverse`), NOT a chain
swap (`bitcoin_boltz_chain`, used only on the on-chain Bitcoin rail). So the Boltz
25,000-sat **chain-swap** minimum does NOT apply; the binding floors are the LNURL
`min_sendable` (100 sats) and Boltz's dynamic reverse-pair minimum (well below
2,000 on Liquid). 2,000 sats is therefore usable — see
`support/funded_la101_fixtures.dart` for the full dust-margin rationale.

Two consequences the spec handles:

- **The credit is `target − swap_fee`.** The reverse swap consumes a service +
  claim fee, so wallet 101 receives less than the amount sent over Lightning. The
  spec waits for any positive balance (a fresh QA wallet 101 starts empty) and
  reports the ACTUAL credited amount.
- **The claim address is server-allocated at claim time**, so the coordinator
  cannot know it a priori. After sync detects the receipt, the spec reads the
  incoming transaction from the app's synced tx list and publishes the ACTUAL
  credited `receipt_address` / `receipt_txid` / `receipt_vout` /
  `receipt_amount_sat` in the `receipt_asserted` checkpoint. The coordinator's
  independent oracle grades that resulting Liquid credit (Lightning leaves no
  chain artifact on the payer→receiver leg — `getpaid-e2e/docs/CHAIN-ORACLE.md`).

## Journey (checkpoint steps)

| step | meaning |
|------|---------|
| `env_check` | fixtures resolved (lane guard, mnemonic, handshake dir all present) |
| `wallet_restored` | default wallets recreated from `GETPAID_FUNDED_MNEMONIC` |
| `lightning_registered` | wallet-owned Lightning Address registered; wallet 101 (Liquid) materialized, autosweep on |
| `addresses_derived` | wallet-101 receive address (informational) + default-Liquid next address derived |
| `handshake_offer_written` | `la101_request.json` published; now awaiting payment |
| `awaiting_payment` | polling wallet-101 sync (status `waiting`/`timeout`) |
| `payment_detected` | wallet-101 balance went positive (the reverse-swap claim) |
| `receipt_asserted` | actual credited address/outpoint/amount resolved from the synced tx list |
| `autosweep_swept` | autosweep fired on sync; sweep txid captured |
| `awaiting_sweep_drain` / `awaiting_sweep_credit` | polling 101 drain + default-Liquid credit |
| `sweep_asserted` | wallet 101 drained; default Liquid wallet credited (before/after balances) |
| `awaiting_return_address` | polling `la101_response.json` for `return_address` |
| `return_address_read` | coordinator's return address read |
| `return_prepared` | drain PSET built; absolute fee computed and asserted `<= max_fee_sat` |
| `return_broadcast` | real Liquid Send broadcast; return txid captured |
| `result_written` | `la101_result.json` published |
| `done` | terminal success |

## Environment variables

Identical to the Page-102 lane (`FUNDED-RUN.md`) except `GETPAID_E2E_LANE` must
equal **`S-REAL-PROD-LA101-FUNDED`** and the default nym is `bbe2ela101<runId>`.
`GETPAID_FUNDED_AMOUNT_SAT` defaults to **2000** (the amount the payer sends over
Lightning). The handshake files are `la101_request.json` / `la101_response.json`
/ `la101_result.json` (schemas `getpaid-la101-funded/v1` and
`getpaid-la101-funded-result/v1`).

## Launch command

Driven by the coordinator (`getpaid-e2e` repo) — see
`scenarios/la101/LA101-RUNBOOK.md`. The coordinator's `launch-spec` step runs:

```bash
fvm flutter test integration_test/get_paid_la101_funded_test.dart \
  -d linux --reporter=expanded
```

with `GETPAID_E2E_LANE=S-REAL-PROD-LA101-FUNDED`, the funded mnemonic, and
`GETPAID_FUNDED_HANDSHAKE_DIR` in the environment. The overall `flutter_test`
timeout is 45 minutes; the payment and return waits are bounded by the
`GETPAID_FUNDED_*_TIMEOUT_SEC` variables.
