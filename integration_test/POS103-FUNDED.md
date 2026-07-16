# Funded POS-103 run (S-REAL-PROD-POS103-FUNDED)

`integration_test/get_paid_pos103_funded_test.dart` drives one authorized,
end-to-end funded journey for the Get Paid **Point of Sale** product (BIP85
wallet-seed index **103**, a Liquid wallet) against **production** Bullnym +
Nostr + the live Liquid network. Two properties make it distinct from the
Page-102 witness: it exercises **real Bullnym settlement** into wallet 103 (not a
direct address send), and it proves **destination isolation** (wallet 101 does
not receive).

**This lane moves real funds.** The spec never pays anything itself: it publishes
the POS **receive surface** (the server-hosted terminal URL) to a handshake
directory, waits for an **external coordinator** to pay it, observes the receipt
and the autosweep through the app's own wallet sync, then returns the balance via
the app's real Liquid Send flow to an address the coordinator writes back. Every
phase prints a machine-readable `CHECKPOINT` line so the coordinator can journal
the run.

It is excluded from the default aggregate run (`tools/gen_all_test.dart` skip
set) and driven only by the coordinator's `scenarios/pos103` Linux lane.

## Real Bullnym settlement (verified at f6eec5127 + bullnym server)

The app mints **no** invoice and renders no till (`pos_architecture.md` DELTA 2):
POS invoice minting is entirely server-side. The app only registers the
wallet-103 `ct_descriptor` (via POS provisioning, `saveDonationPage(kind=pos)`)
and observes receipt via wallet sync.

The POS terminal is a keyless server PWA at `/<nym>/pos`; its checkout endpoint is
`POST /:nym/pos/invoice`. On payment, Bullnym derives a Liquid address from the
`(nym,'pos')` descriptor and delivers L-BTC there. The chosen rail is
**Lightning**: the coordinator pays the terminal's Lightning invoice, Boltz does a
**reverse** swap (LN→L-BTC) and claims the output into a wallet-103 descriptor
address. A reverse (submarine) swap is **not** a Boltz chain swap, so the
25,000-sat chain-swap minimum does **not** apply — only the server's LNURL
`min_sendable`. The settlement address is chosen by the server (its own descriptor
cursor), so the spec does not pre-derive a pay target: it proves receipt by the
wallet-103 **balance** rise on sync, then reads the actual receipt outpoint back
from the wallet's own UTXO set and publishes it for the coordinator's oracle.

## App-owned wallet + fund-safety capture

The recipient wallet is **created on-device** by the normal wallet-creation flow
(`CreateDefaultWalletsUsecase.execute()` with no mnemonic → the app generates and
owns a fresh seed, auto-backed-up over Nostr). No mnemonic is injected. Before any
funds move, the app's own show-mnemonic/backup-export path
(`GetMnemonicFromFingerprintUsecase`) captures the recovery material to a durable
**mode-0600** file, one per run, at `GETPAID_FUNDED_SEED_CAPTURE_DIR` (default
`/home/francis/bull-bitcoin-workspace/.secrets-carry/getpaid-qa-seeds/`). The
words/passphrase are written only to that local file and are **never** logged,
printed, committed, or emitted on the handshake — only the capture-file PATH and
the master fingerprint appear in a checkpoint.

## Destination isolation

POS and the Lightning Address share **one nym** but never a settlement
destination: POS settles to wallet 103, the `nym@domain` LN address to wallet 101
(server routes the pos checkout to the `(nym,'pos')` descriptor, distinct from the
`users`/101 descriptor). The spec registers the shared LN address first
(materializing wallet 101), baselines it, and after the payment asserts wallet 103
received the funds AND wallet 101 is unchanged (`isolation_asserted`). It publishes
the wallet-101 receive address so the coordinator's independent oracle can prove no
on-chain transaction touched it.

## Journey (checkpoint steps)

| step | meaning |
|------|---------|
| `env_check` | fixtures resolved (lane guard, handshake dir, seed-capture dir all present) |
| `wallet_created` | default wallets CREATED on-device from a fresh app-owned seed |
| `seed_captured` | recovery material written to the mode-0600 capture file (PATH + fingerprint only) |
| `lightning_registered` | wallet-owned Lightning Address nym registered (POS reuses it; materializes wallet 101) |
| `wallet101_resolved` | Lightning Address wallet 101 resolved (the isolation guard's subject) |
| `pos_provisioned` | POS terminal provisioned; wallet 103 (Liquid) materialized, descriptor registered, autosweep on |
| `addresses_derived` | wallet-103 reference + wallet-101 + default-Liquid receive addresses derived |
| `handshake_offer_written` | `pos103_request.json` published (terminal URL = pay target); now awaiting payment |
| `awaiting_payment` | polling wallet-103 sync for the Bullnym settlement (status `waiting` / `timeout`) |
| `payment_detected` | wallet-103 balance reached the target amount |
| `receipt_asserted` | app wallet state reflects the settlement on wallet 103 |
| `receipt_outpoint` | the on-chain receipt outpoint (txid:vout) read back from wallet 103's UTXO set |
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

`status` is `ok` for milestones, `waiting`/`timeout` for polls. Only non-secret
values are ever emitted (addresses, txids, amounts, balances, run id, nym,
capture-file PATH) — **never the mnemonic, passphrase, or any signer material.**
Balances are strings because they are `BigInt` satoshis.

## Environment variables

Shared `GETPAID_FUNDED_*` contract; only the lane guard value differs from the
other funded witnesses. **No mnemonic** variable — the app owns its seed.

| var | required | default | meaning |
|-----|----------|---------|---------|
| `GETPAID_E2E_LANE` | yes | — | must equal `S-REAL-PROD-POS103-FUNDED` |
| `GETPAID_FUNDED_HANDSHAKE_DIR` | yes | — | existing writable directory for the handshake files |
| `GETPAID_FUNDED_SEED_CAPTURE_DIR` | no | `.secrets-carry/getpaid-qa-seeds` | durable mode-0600 dir for the per-run recovery capture |
| `GETPAID_FUNDED_NYM` | no | `bbe2epos103<runId>` | nym to register / reuse (sanitized to `[a-z0-9]`) |
| `GETPAID_FUNDED_RUN_ID` | no | epoch ms in base36 | run correlation id |
| `GETPAID_FUNDED_AMOUNT_SAT` | no | `2000` | amount wallet 103 must receive (LN reverse-swap; no 25k floor) |
| `GETPAID_FUNDED_MAX_FEE_SAT` | no | `10000` | ceiling asserted on the return-send absolute fee |
| `GETPAID_FUNDED_FEE_RATE` | no | `0.1` | Liquid fee rate (sat/vB) for the return drain |
| `GETPAID_FUNDED_PAYMENT_TIMEOUT_SEC` | no | `900` | max wait for the payment / sweep to settle |
| `GETPAID_FUNDED_RETURN_TIMEOUT_SEC` | no | `900` | max wait for the coordinator's return address |
| `GETPAID_FUNDED_POLL_INTERVAL_SEC` | no | `15` | poll interval for all waits |

`--dart-define` fallbacks exist for `GETPAID_E2E_LANE`, `GETPAID_FUNDED_NYM`,
`GETPAID_FUNDED_RUN_ID`, `GETPAID_FUNDED_HANDSHAKE_DIR`, and
`GETPAID_FUNDED_SEED_CAPTURE_DIR`.

Fail-fast refusals: if the handshake dir is unset/missing, OR the seed-capture dir
cannot be created, fixtures construction throws before any wallet or network work
— a funded journey with no channel back to the coordinator, or nowhere durable to
capture an app-owned wallet's recovery material, must not run.

## Handshake contract

All files live in `GETPAID_FUNDED_HANDSHAKE_DIR`, written atomically (temp +
rename).

### 1. `pos103_request.json` — spec → coordinator (at `handshake_offer_written`)

```json
{
  "schema": "getpaid-pos103-funded/v1",
  "run_id": "abc123",
  "nym": "bbe2epos103abc123",
  "network": "liquid-mainnet",
  "receive_rail": "lightning",
  "terminal_url": "https://.../<nym>/pos",
  "pos103_reference_address": "lq1...",
  "lightning_address_receive_address": "lq1...",
  "default_liquid_address": "lq1...",
  "target_amount_sat": 2000,
  "max_fee_sat": 10000,
  "status": "awaiting_payment",
  "written_at": "2026-07-16T00:00:00.000Z"
}
```

The coordinator pays the **`terminal_url`** POS checkout over Lightning; Bullnym
settles into wallet 103. `pos103_reference_address` is for the record only (the
real settlement address is server-derived). `lightning_address_receive_address` is
used only to assert (via the independent oracle) that **no** transaction touched
wallet 101.

### 2. `pos103_response.json` — coordinator → spec (from `awaiting_return_address`)

```json
{ "return_address": "lq1...", "payment_txid": "<optional>" }
```

### 3. `pos103_result.json` — spec → coordinator (at `result_written`)

```json
{
  "schema": "getpaid-pos103-funded-result/v1",
  "run_id": "abc123",
  "nym": "bbe2epos103abc123",
  "network": "liquid-mainnet",
  "receive_rail": "lightning",
  "pos103_receipt_txid": "<liquid txid>",
  "pos103_receipt_vout": 0,
  "pos103_receipt_amount_sat": "2000",
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
export GETPAID_FUNDED_HANDSHAKE_DIR="$HS"
# optional: GETPAID_FUNDED_SEED_CAPTURE_DIR, GETPAID_FUNDED_AMOUNT_SAT,
# GETPAID_FUNDED_NYM, GETPAID_FUNDED_RUN_ID, GETPAID_FUNDED_*_TIMEOUT_SEC ...

fvm flutter test integration_test/get_paid_pos103_funded_test.dart \
  -d linux --reporter=expanded
```

Normally launched by the coordinator's `scenarios/pos103` Linux lane, not by hand
— see `getpaid-e2e` `docs/POS103-RUNBOOK.md`.
