# Funded Page-102 run (S-REAL-PROD-PAGE102-FUNDED)

`integration_test/get_paid_page102_funded_test.dart` drives one authorized,
end-to-end funded journey for the Get Paid **Payment Page** product (BIP85
wallet-seed index **102**, a Liquid wallet) against **production** Bullnym +
Nostr + the live Liquid network. It exercises **real Bullnym settlement** into
wallet 102 over the page's **Lightning rail** (not a direct address send).

**This lane moves real funds.** The spec never pays anything itself: it publishes
the page's Lightning **checkout surface** (the server-hosted public URL) to a
handshake directory, waits for an **external coordinator** to pay it, observes
the receipt and the autosweep through the app's own wallet sync, then returns the
balance via the app's real Liquid Send flow to an address the coordinator writes
back. Every phase prints a machine-readable `CHECKPOINT` line so the coordinator
can journal the run.

It is excluded from the default aggregate run (`tools/gen_all_test.dart` skip
set) and driven only by the coordinator's `scenarios/page102` Linux lane.

## Real Bullnym settlement over Lightning (verified at f6eec5127 + bullnym server)

The app mints no invoice and derives no pay target. It only provisions the page
(`savePaymentPage`, which registers the wallet-102 `ct_descriptor`) and observes
receipt via wallet sync. The page's public URL is a keyless server checkout
surface; paying it over Lightning drives bullnym's LNURL / donation
checkout-invoice path (`bullnym` `lnurl.rs`, `config.rs` "Donation/payment-page
APIs and donation checkout invoice sessions"), which creates a Boltz **reverse**
submarine swap (`boltz.rs::create_reverse_swap`, LN->L-BTC) and claims the output
(`claimer.rs`) into a wallet-102 address derived from the page's `(nym, donation)`
descriptor — distinct from the Lightning Address `users`/101 descriptor. A
reverse (submarine) swap is **not** a Boltz chain swap, so the 25,000-sat
chain-swap minimum does **not** apply — only the server's LNURL `min_sendable`.
The settlement address is chosen by the server, so the spec does not pre-derive a
pay target: it proves receipt by the wallet-102 **balance** rise on sync, then
reads the actual receipt outpoint back from the wallet's own UTXO set and
publishes it for the coordinator's oracle.

Because Liquid outputs are **confidential** (blinded amount), the on-chain credit
amount cannot be verified by a public chain explorer. The spec publishes the
**app-read** receipt amount; amount integrity is proven by the coordinator's
known guarded-payer debit + global conservation (opening − fees = closing), not
by on-chain amount inspection. The reverse swap deducts a service fee, so wallet
102 nets slightly under `target_amount_sat`.

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

## Journey (checkpoint steps)

| step | meaning |
|------|---------|
| `env_check` | fixtures resolved (lane guard, handshake dir, seed-capture dir all present) |
| `wallet_created` | default wallets CREATED on-device from a fresh app-owned seed |
| `seed_captured` | recovery material written to the mode-0600 capture file (PATH + fingerprint only) |
| `lightning_registered` | wallet-owned Lightning Address nym registered (the page save reuses it) |
| `page_created` | Payment Page saved; wallet 102 (Liquid) provisioned, descriptor registered, autosweep on |
| `addresses_derived` | wallet-102 reference + default-Liquid receive addresses derived |
| `handshake_offer_written` | `page102_request.json` published (page checkout URL = pay target); now awaiting payment |
| `awaiting_payment` | polling wallet-102 sync for the Bullnym settlement (status `waiting` / `timeout`) |
| `payment_detected` | wallet-102 balance rose above the dust floor (reverse-swap net) |
| `receipt_asserted` | app wallet state reflects the settlement on wallet 102 |
| `receipt_outpoint` | the on-chain receipt outpoint (txid:vout) + app-read amount read back from wallet 102's UTXO set |
| `autosweep_swept` | autosweep fired on sync; sweep txid captured |
| `awaiting_sweep_drain` / `awaiting_sweep_credit` | polling 102 drain + default-Liquid credit |
| `sweep_asserted` | wallet 102 drained; default Liquid wallet credited (before/after balances) |
| `awaiting_return_address` | polling `page102_response.json` for `return_address` |
| `return_address_read` | coordinator's return address read |
| `return_prepared` | drain PSET built; absolute fee computed and asserted `<= max_fee_sat` |
| `return_broadcast` | real Liquid Send broadcast; return txid captured |
| `result_written` | `page102_result.json` published |
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
| `GETPAID_E2E_LANE` | yes | — | must equal `S-REAL-PROD-PAGE102-FUNDED` |
| `GETPAID_FUNDED_HANDSHAKE_DIR` | yes | — | existing writable directory for the handshake files |
| `GETPAID_FUNDED_SEED_CAPTURE_DIR` | no | `.secrets-carry/getpaid-qa-seeds` | durable mode-0600 dir for the per-run recovery capture |
| `GETPAID_FUNDED_NYM` | no | `bbe2epage102<runId>` | nym to register / reuse (sanitized to `[a-z0-9]`) |
| `GETPAID_FUNDED_RUN_ID` | no | epoch ms in base36 | run correlation id |
| `GETPAID_FUNDED_AMOUNT_SAT` | no | `2000` | target wallet 102 must receive (LN reverse-swap; no 25k floor; nets slightly under after the swap fee) |
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

### 1. `page102_request.json` — spec → coordinator (at `handshake_offer_written`)

```json
{
  "schema": "getpaid-page102-funded/v2",
  "run_id": "abc123",
  "nym": "bbe2epage102abc123",
  "network": "liquid-mainnet",
  "receive_rail": "lightning",
  "page_checkout_url": "https://.../<nym>",
  "page102_reference_address": "lq1...",
  "default_liquid_address": "lq1...",
  "target_amount_sat": 2000,
  "max_fee_sat": 10000,
  "status": "awaiting_payment",
  "written_at": "2026-07-16T00:00:00.000Z"
}
```

The coordinator pays the **`page_checkout_url`** over Lightning; Bullnym
reverse-swaps and settles into wallet 102. `page102_reference_address` is for the
record only (the real settlement address is server-derived).

### 2. `page102_response.json` — coordinator → spec (from `awaiting_return_address`)

```json
{ "return_address": "lq1...", "payment_txid": "<optional>" }
```

### 3. `page102_result.json` — spec → coordinator (at `result_written`)

```json
{
  "schema": "getpaid-page102-funded-result/v2",
  "run_id": "abc123",
  "nym": "bbe2epage102abc123",
  "network": "liquid-mainnet",
  "receive_rail": "lightning",
  "page102_receipt_txid": "<liquid txid>",
  "page102_receipt_vout": 0,
  "page102_receipt_amount_sat": "1930",
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

`page102_receipt_amount_sat` is the app-read (wallet-unblinded) settled amount —
the coordinator's chain oracle proves the outpoint was spent by the autosweep
(structural, confidential-safe) but cannot read the amount on-chain.

## Launch command

```bash
export GETPAID_E2E_LANE=S-REAL-PROD-PAGE102-FUNDED
export GETPAID_FUNDED_HANDSHAKE_DIR="$HS"
# optional: GETPAID_FUNDED_SEED_CAPTURE_DIR, GETPAID_FUNDED_AMOUNT_SAT,
# GETPAID_FUNDED_NYM, GETPAID_FUNDED_RUN_ID, GETPAID_FUNDED_*_TIMEOUT_SEC ...

fvm flutter test integration_test/get_paid_page102_funded_test.dart \
  -d linux --reporter=expanded
```

Normally launched by the coordinator's `scenarios/page102` Linux lane, not by
hand — see `getpaid-e2e` `docs/PAGE102-RUNBOOK.md`.
