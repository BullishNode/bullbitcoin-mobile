# Lightning Address

A user nym (`alice@bullpay.ca`) registered with the bullnym pay service.
Incoming Lightning payments are settled on Liquid via Boltz reverse submarine
swaps into a BIP85-derived Lightning Address receive wallet on the device.
Funds are eligible for Get Paid autosweep when the wallet is classified as an
external receive wallet and autosweep is enabled for that purpose.

When sending TO a Lightning Address, the app may use LUD-22 to pay directly on
Liquid and skip the Boltz swap. LUD-22 probing/proof requests can reveal sender
intent to the recipient service, so they must be deferred until the user
confirms direct Liquid payment. Do not add a separate consent/disclosure step;
the privacy boundary is the timing of the direct-pay action itself.

## BIP85 derivations

| What | Path | Source |
|---|---|---|
| Lightning Address receive wallet mnemonic | BIP85 index 75 → 12-word mnemonic | `external_receive_wallet_purpose.dart` |
| Bullnym auth Nostr identity | BIP85 `9000'/2'/1'` → 32-byte secret | `features/nostr_identity` |
| NIP-05 verification Nostr identity | BIP85 `9000'/3'/1'` → 32-byte secret | `features/nostr_identity` |

The receive wallet is created from the child mnemonic and labeled by external
receive wallet purpose. `GetExternalReceiveWalletUsecase` finds it by wallet
manifest origin metadata, not by label. Lightning Address provisions the
`Lightning Address-LBTC` wallet today.
Payment Page provisions `Payment Page-LBTC` when saving an enabled page, but
descriptor binding belongs to the future server/API phase. BTCPay pairing
provisions `BTCPay-LBTC` and/or `BTCPay-BTC` path-77 wallets after a valid
SamRock pairing request starts. Payment Page and BTCPay wallets are not created
from Lightning Address flows.
The Nostr path is independent from the
receive-wallet index; `75` is not reused as a Nostr identity number.

Wallet manifest work uses reserved BIP85 Nostr application `9000` identities
for wallet manifest, Bullnym server authentication, and NIP-05 verification.
Registration/auth updates use the Bullnym server-authentication key, while
NIP-05 profile publish/clear uses the NIP-05 verification key. There is no
legacy manifest migration path for internal pre-release state.

## Use cases

Lightning Address-specific use cases live in
`lib/features/lightning_address/domain/usecases/`; shared external receive
wallet use cases live behind
`lib/features/external_receive_wallets/public/external_receive_wallets.dart`.

| Use case | Inputs | Outputs |
|---|---|---|
| `CreateExternalReceiveWalletUsecase` | environment, purpose/account key, publish-manifest flag | `Wallet` |
| `GetExternalReceiveWalletUsecase` | environment, purpose/account key | `Wallet?` (manifest origin match) |
| `RegisterLightningAddressUsecase` | nym, environment | `String` (`nym@domain`) |
| `DeleteLightningAddressUsecase` | nym | `NymQuota` |
| `SweepExternalReceiveWalletUsecase` | isTestnet, purpose, expected synced wallet id | `String?` (txid) |

Setter use cases take `…Command` objects; getters take named params.

## Wire: register / delete / lookup

Lightning Address does not build Bullpay signature bytes itself. Its use cases
derive the approved Nostr key handle and pass semantic fields to
`PayServicePort`. The data adapter delegates to
`features/bullnym/BullnymClient`, which owns the deployed
`bullpay-la-v2` wire contract:

```
bullpay-la-v2\x00<action>\x00<npub_hex>\x00<nym_or_empty>\x00(<field>\x00)*<timestamp>
```

| Action | Payload fields |
|---|---|
| `register` | nym as `nym_or_empty`, post-nym fields `ct_descriptor`, `verification_npub` |
| `delete` | (none) |

Schnorr-signed (BIP-340). Server enforces ±300 s freshness.

## LUD-22 send

`try_liquid_direct_pay_usecase.dart`:

1. Validate `<nym>@<domain>` against strict regexes (LUD-16 local-part + RFC 1035 hostname).
2. Run only after the user has confirmed direct Liquid payment.
3. `GET https://<domain>/.well-known/lnurlp/<nym>` (no redirects).
4. Require `payment_methods` array containing `"L-BTC"`.
5. Validate `metadata.callback`: `scheme == 'https' && host == domain`.
6. POST proof of funds (`outpoint`, `pubkey`, `sig`) via the same callback.
7. Server returns `{ "L-BTC": { "address": "lq1q…" } }`; the app builds a
   Liquid payment request from the returned address.

`SendState.lud22OriginalAddress` preserves the user-pasted nym for display
on the confirm screen.

## Auto-sweep

`WalletBloc._onWalletSyncFinished` classifies the synced wallet through
manifest-backed external receive wallet ids. If the synced wallet is a Liquid
external receive wallet and its purpose has autosweep enabled in Get Paid
settings, `WalletBloc` calls `ExternalReceiveWalletsFacade.sweep()` with the
expected synced wallet id. Missing, mismatched, or dust-only wallets return
`null` and do not create wallets. Sweep:

1. Find the external receive wallet by purpose. Bail if missing or balance ≤
   100 sats (dust).
2. `generateNewReceiveAddress(default Liquid)` — fresh index per sweep.
3. Build drain PSET → sign → broadcast.
4. Label the resulting txid with the external receive wallet purpose label.

## Recovery

Automatic seed-restore wallet recreation is not owned by Lightning Address or
external receive wallets. Onboarding physical seed recovery and RecoverBull wire
it through the neutral `wallet_manifest` facade. That path restores only wallets
listed in the encrypted wallet manifest, does not scan reserved fallback paths,
and does not call Lightning Address server recovery.

Lightning Address server-record recovery is not exposed through the cross-
feature facade. Any future server-state recovery flow must be designed as an
explicit Lightning Address product action, separate from automatic seed-restore
wallet manifest recovery.

The tradeoff of manifest-authoritative recovery is that it may recreate empty
external receive wallets, adding wallets to normal sync and making future syncs
slower. Empty child paths remain uncreated unless a manifest proves that the
wallet existed, the user explicitly runs Get Paid Advanced manual recovery, or
the product feature lazily creates the wallet during normal setup/pairing.

## Hide wallet

`WalletBloc` asks the neutral external receive wallet facade for
manifest-backed wallet ids. The facade applies Get Paid hide-on-home settings
for Lightning Address, Payment Page, and BTCPay Liquid wallets by returning a
hidden wallet id set. The wallet list filters that set directly; it does not
call Lightning Address settings or classify wallets by reserved labels.

## Privacy boundaries

- Nostr secret keys stay behind the `NostrIdentity` / `NostrKeychainHandle`
  callback boundary. `toString()` prints only the public key.
- LUD-22 metadata/proof requests are not used as an automatic preflight before
  the user confirms direct Liquid payment.
- LUD-22 callback is pinned to `https` + the metadata host. Redirects
  disabled on both metadata fetch and callback POST.
- Sweep destination is a fresh receive index per sweep (not address-reused).

## Files

- `domain/usecases/` — Lightning Address registration, deletion, lookup, and Nostr profile use cases
- `../external_receive_wallets/public/external_receive_wallets.dart` — public external receive wallet facade boundary
- `domain/lightning_address_key_derivation.dart` — xprv + Nostr derivation helpers
- `domain/ports/pay_service_port.dart` — abstract HTTP interface
- `domain/lightning_address_errors.dart` — feature errors
- `data/datasources/pay_service_datasource.dart` — adapter to shared Bullnym client + Hive address cache
- `data/datasources/lightning_address_settings_datasource.dart` — Hive: Nostr publish result cache
- `presentation/lightning_address_cubit.dart` — screen state machine
- `public/lightning_address_facade.dart` — cross-feature surface
- `ui/lightning_address_settings_screen.dart` — registration + activated views
- `lightning_address_locator.dart` — DI

## Server

`bullnym/pay-service` — register/update/delete/lookup, LUD-16 metadata, LUD-22
callback, Boltz reverse-swap orchestration.

## Known limitations

**Clear-profile failure on deactivation is silent.** When the user deactivates,
the cubit fires a background `clear_lightning_address_nostr_profile_usecase`
that publishes an empty kind:0. If the broadcast reaches zero relays, the
failure is logged only — there is no UI surface and no in-app retry. This is
intentional:
- `bullpay.ca`'s NIP-05 endpoint stops resolving the deactivated nym
  immediately; the namespace is reclaimed regardless of relay state.
- kind:0 events are timestamp-replaceable; any later register on the same
  npub overwrites the old metadata.
- Users who want to scrub their old kind:0 from relays can broadcast an empty
  kind:0 from any external Nostr client.
