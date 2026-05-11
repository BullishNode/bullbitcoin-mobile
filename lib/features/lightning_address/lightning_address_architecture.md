# Lightning Address

A user nym (`alice@bullpay.ca`) registered with the bullnym pay service.
Incoming Lightning payments are settled on Liquid via Boltz reverse submarine
swaps into a BIP85-derived Liquid wallet on the device. Funds are auto-swept
to the default Liquid wallet on every sync.

When sending TO a Lightning Address, if the recipient's pay service advertises
LUD-22 with `payment_method=L-BTC`, the app pays directly on Liquid and skips
the Boltz swap.

## BIP85 derivations

| What | Path | Source |
|---|---|---|
| LA wallet mnemonic | BIP85 index 75 → 12-word mnemonic | `lightning_address_constants.dart` |
| Nostr identity | BIP85 `86'/1'/1'` → 32-byte secret | `nostr_identity.dart` (Nostr application 86) |

The LA wallet is created from the child mnemonic and labeled
`"Lightning Address"`. `GetLightningAddressWalletUsecase` finds it by label.
The Nostr path is independent from the LA wallet index; `75` is not reused as
a Nostr identity number.

## Use cases

`lib/features/lightning_address/domain/usecases/`

| Use case | Inputs | Outputs |
|---|---|---|
| `CreateLightningAddressWalletUsecase` | environment | `Wallet` |
| `GetLightningAddressWalletUsecase` | environment | `Wallet?` (label match) |
| `RegisterLightningAddressUsecase` | nym, environment | `String` (`nym@domain`) |
| `DeleteLightningAddressUsecase` | nym | `NymQuota` |
| `RecoverLightningAddressUsecase` | environment | `String?` |
| `SweepLightningAddressWalletUsecase` | isTestnet | `String?` (txid) |

Setter use cases take `…Command` objects; getters take named params.

## Wire: register / delete / lookup

Lightning Address does not build Bullpay signature bytes itself. Its use cases
derive the approved Nostr key handle and pass semantic fields to
`PayServicePort`. The data adapter delegates to
`features/get_paid/shared/bullnym/BullnymClient`, which owns the deployed
`bullpay-la-v2` wire contract:

```
bullpay-la-v2\x00<action>\x00<npub_hex>\x00<nym_or_empty>\x00(<field>\x00)*<timestamp>
```

| Action | Payload fields |
|---|---|
| `register` | nym as `nym_or_empty`, post-nym field `ct_descriptor` |
| `delete` | (none) |

Schnorr-signed (BIP-340). Server enforces ±300 s freshness.

## LUD-22 send

`try_liquid_direct_pay_usecase.dart`:

1. Validate `<nym>@<domain>` against strict regexes (LUD-16 local-part + RFC 1035 hostname).
2. `GET https://<domain>/.well-known/lnurlp/<nym>` (no redirects).
3. Require `payment_methods` array containing `"L-BTC"`.
4. Validate `metadata.callback`: `scheme == 'https' && host == domain`.
5. POST proof of funds (`outpoint`, `pubkey`, `sig`) via the same callback.
6. Server returns `{ "L-BTC": { "address": "lq1q…" } }` → BIP21 Liquid URI.

`SendState.lud22OriginalAddress` preserves the user-pasted nym for display
on the confirm screen.

## Auto-sweep

`WalletBloc._onWalletSyncFinished` (for the default Liquid wallet only) calls
`LightningAddressFacade.sweep()` if `shouldAutoSweep()` is true and the
auto-swap executor is idle. Sweep:

1. `getWallet(LA)`. Bail if balance ≤ 100 sats (dust).
2. `generateNewReceiveAddress(default Liquid)` — fresh index per sweep.
3. Build drain PSET → sign → broadcast.
4. Label the resulting txid `"Lightning Address"`.

## Recovery

`LightningAddressFacade.recoverIfNeeded()` runs after `WalletStarted` on
mnemonic import / RecoverBull. Fire-and-forget; does NOT run on fresh
install or normal startup.

1. If `getStoredAddress()` is non-null, exit.
2. Derive Nostr identity, `lookupByNpub()` on the pay service.
   - 404 → no record, exit.
   - 5xx / timeout → throws `PayServiceException`; caller catches and exits
     so recovery retries on the next launch.
3. If active record: create wallet (if missing) + store the address.

## Hide wallet

`WalletBloc._onStarted / _onRefreshed` calls
`LightningAddressFacade.isWalletHidden()`; if true, the LA wallet is filtered
out of the wallet list. `SendCubit.loadWalletWithRatesAndFees` always filters
the LA wallet out of selectable send sources.

## Privacy boundaries

- Nostr secret keys stay behind the `NostrIdentity` / `NostrKeychainHandle`
  callback boundary. `toString()` prints only the public key.
- LUD-22 callback is pinned to `https` + the metadata host. Redirects
  disabled on both metadata fetch and callback POST.
- Sweep destination is a fresh receive index per sweep (not address-reused).

## Files

- `domain/usecases/` — six use cases above
- `domain/lightning_address_key_derivation.dart` — xprv + Nostr derivation helpers
- `domain/ports/pay_service_port.dart` — abstract HTTP interface
- `domain/lightning_address_errors.dart` — feature errors
- `data/datasources/pay_service_datasource.dart` — adapter to shared Bullnym client + Hive address cache
- `data/datasources/lightning_address_settings_datasource.dart` — Hive: auto-sweep, hide-wallet, stored address
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
