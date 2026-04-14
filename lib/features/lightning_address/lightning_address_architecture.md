# Lightning Address Feature Architecture

## Overview

Users register a nym (e.g. `francis@bullpay.ca`) with the bullnym pay service.
Incoming Lightning payments are settled on Liquid via Boltz reverse submarine
swaps. The mobile app creates a BIP85-derived Liquid wallet to receive these
funds and automatically sweeps them to the default Instant Payments wallet.

When sending TO a Lightning Address, if the recipient's server supports LUD-22
and advertises Liquid, the app pays directly on Liquid — bypassing the Boltz
swap entirely.

## BIP85 Derivation Paths

### Lightning Address Wallet (index 75)
```
Master Seed
  → BIP85 mnemonic derivation at index 75
  → 12-word child mnemonic
  → LWK Liquid wallet (CT descriptor shared with pay service)
```
Index 75 derived from "boltz": b(2)+o(15)+l(12)+t(20)+z(26) = 75.
The wallet is labeled "Lightning Address" and identified by this label.

### Nostr Identity (application 86, identity 75, account 0)
```
Master Seed
  → BIP32 xprv
  → BIP85 entropy at path 86'/75'/0'
  → 32-byte secret key → Nostr keypair (nsec/npub)
```
Application 86 is the NIP-06 Nostr application number. Identity index 75
matches the wallet index. Used for:
- Schnorr signing registration/deletion requests (BIP-340)
- NIP-05 identity (`npub` stored on server)
- Nostr profile publishing (kind 0 with `nip05` and `lud16` fields)

## Domain

### Ports
- **PayServicePort** — abstract interface for pay service HTTP calls
  (register, delete, lookup, store/get address). Implemented by
  PayServiceDatasource. Domain use cases depend on the port, not the concrete
  datasource.

### Use Cases
- **CreateLightningAddressWalletUsecase** — BIP85 child mnemonic → LWK wallet
- **GetLightningAddressWalletUsecase** — find wallet by label
- **RegisterLightningAddressUsecase** — create wallet + derive Nostr key + sign + call server + publish Nostr profile
- **DeleteLightningAddressUsecase** — sign "delete" + call server + clear Nostr profile
- **SweepLightningAddressWalletUsecase** — drain LA wallet to Instant Payments, label tx "Lightning Address"
- **RecoverLightningAddressUsecase** — derive Nostr key + check server for existing registration + create wallet if found

### Error Types
- `LightningAddressWalletAlreadyExistsException`
- `LightningAddressWalletNotFoundException`
- `LightningAddressSweepException`
- `LightningAddressNoDefaultWalletException`
- `LightningAddressRegistrationException` (mapped from PayServiceException)

### Key Derivation
`lightning_address_key_derivation.dart` — shared helpers:
- `deriveDefaultWalletXprv()` — get default Bitcoin wallet → seed → xprv
- `deriveNostrIdentityForLightningAddress()` — xprv → NostrIdentity

## LUD-22: Liquid Direct Pay

When sending to a Lightning Address, the app checks if the server supports
Liquid via LUD-22 currency negotiation. If it does, the callback is called
with `&network=liquid` and the server returns a Liquid address directly instead
of a Lightning invoice.

```
User enters: francis@bullpay.ca
  → LNURL metadata: check for currencies[].network == "liquid"
  → If supported: callback with &network=liquid → get Liquid address
  → Confirm screen shows: To: francis@bullpay.ca, Network: Liquid
  → Direct Liquid payment (no Boltz swap, no fees, no trust)
```

The original Lightning Address is preserved in `SendState.lud22OriginalAddress`
so the confirm screen displays the nym, not the resolved Liquid address.

## Presentation

`LightningAddressCubit` — owns screen state (loading, registering, address,
error, walletExists, previousNym). UI dispatches `checkStatus()`,
`registerNym()`, `deleteAddress()`.

Settings screen shows:
- Registration form (choose nym) with StatusScreen progress animation
- Activated view: address display, tap-to-copy, auto-sweep toggle, hide wallet toggle, deactivate button with confirmation dialog

## Data Flows

### Registration
```
Settings UI → LightningAddressCubit.registerNym()
  → RegisterLightningAddressUsecase
    → Create/get wallet (BIP85 index 75)
    → Derive Nostr key (BIP85 86'/75'/0')
    → Sign(nym + ctDescriptor) with BIP-340 schnorr
    → PayServicePort.register() → server returns "nym@bullpay.ca"
    → NostrRelayClient.publishProfile(nip05, lud16) to 7 relays
```

### Auto-Sweep
```
WalletBloc._onWalletSyncFinished (default Liquid, not LA wallet)
  → LightningAddressFacade.shouldAutoSweep()
  → LightningAddressFacade.sweep()
    → SweepLightningAddressWalletUsecase
      → buildPset(drain: true) → sign → broadcast
      → LabelsFacade.store("Lightning Address" label on txid)
```

### Recovery (mnemonic import / RecoverBull only)
```
ImportMnemonicRouter / RecoverBullBloc (after WalletStarted)
  → LightningAddressFacade.recoverIfNeeded()
    → RecoverLightningAddressUsecase
      → Check stored address (skip if exists)
      → Derive Nostr key → PayServicePort.lookupByNpub()
      → If found + active: create wallet + store address
```
Non-blocking, fire-and-forget. Does NOT run on new wallet creation or normal
app startup.

### Wallet Hiding
```
WalletBloc._onStarted / _onRefreshed
  → Check if any wallet has label "Lightning Address" (zero-cost if none)
  → If yes: check isWalletHidden() setting → filter from list
```

## Concurrency

- Sweep only fires on default Liquid wallet sync (not LA wallet's own sync)
- Guard: `!state.autoSwapExecuting` prevents sweep during auto-swap
- No dedicated sweep mutex — acceptable since sweep is idempotent

## Feature Dependencies

- **Depends on:** core/wallet, core/bip85, core/seed, core/blockchain, core/fees, core/nostr, features/labels
- **Depended on by:** wallet (via public facade), settings (via public facade + cubit), import_mnemonic (via facade), recoverbull (via facade)
- **Cross-feature imports:** settings_router imports cubit + UI directly (follows codebase convention for routing)
