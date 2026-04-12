# Lightning Address Feature Architecture

## Overview

The lightning_address feature creates a BIP85-derived Liquid wallet dedicated to
receiving Lightning Address payments via Boltz reverse submarine swaps. Funds
that arrive in this wallet are automatically swept to the user's default Liquid
wallet on every sync cycle.

## Domain

### Use Cases

- **CreateLightningAddressWalletUsecase** — Derives a BIP85 child mnemonic at
  fixed index 75 (from "boltz": b+o+l+t+z = 2+15+12+20+26) from the default
  Bitcoin wallet, creates a Liquid wallet labeled "Lightning Address". Idempotent
  check via GetLightningAddressWalletUsecase (composition, not duplication).

- **GetLightningAddressWalletUsecase** — Finds the lightning address wallet by
  label match within the current environment. Returns null if not activated.

- **SweepLightningAddressWalletUsecase** — Drains all funds above dust threshold
  from the lightning address wallet to the default Liquid wallet. Uses existing
  LiquidWalletRepository.buildPset(drain: true), signPset, and
  BroadcastLiquidTransactionUsecase. Returns null (no-op) if wallet doesn't
  exist or balance is at/below dust.

### Error Types

- `LightningAddressWalletAlreadyExistsException` — create called when wallet exists
- `LightningAddressWalletNotFoundException` — operation requires wallet that doesn't exist
- `LightningAddressSweepException` — sweep failed (e.g., no default Liquid wallet)

## Public Facade

`LightningAddressFacade` is the only cross-feature interface. Exposes:
- `walletLabel` constant — used by wallet feature to filter display
- `isLightningAddressWallet(Wallet)` — static predicate
- `sweep(isTestnet:)` — triggers sweep from WalletBloc

## Data Flows

### Activation
```
Settings UI → CreateLightningAddressWalletUsecase
  → Bip85Repository.deriveMnemonic(index: 75)
  → SeedRepository.createFromMnemonic()
  → WalletRepository.createWallet(label: "Lightning Address")
```

### Auto-Sweep (triggered by wallet sync)
```
WalletBloc._onWalletSyncFinished (default Liquid wallet only)
  → LightningAddressFacade.sweep()
    → SweepLightningAddressWalletUsecase.execute()
      → GetLightningAddressWalletUsecase (find wallet)
      → Check balance > dust
      → WalletAddressRepository.getLastUnusedReceiveAddress (destination)
      → LiquidWalletRepository.buildPset(drain: true)
      → LiquidWalletRepository.signPset()
      → BroadcastLiquidTransactionUsecase.execute()
```

### Home Screen Filtering
```
WalletBloc._filterDisplayWallets()
  → LightningAddressFacade.isLightningAddressWallet()
  → Excluded from state.wallets (and therefore totalBalance)
```

## Concurrency

- `lightningAddressSweepExecuting` flag in WalletState prevents concurrent sweeps
- Sweep only fires on default Liquid wallet sync (not on LA wallet's own sync)

## Recovery

The wallet is deterministically derived from the master BIP85 seed at a fixed
index. On restore, the app re-derives the child mnemonic, creates the LWK
wallet, syncs to detect UTXOs, and auto-sweeps on next sync.

## Feature Dependencies

- **Depends on:** core/wallet, core/bip85, core/seed, core/blockchain, core/fees
- **Depended on by:** wallet (via public facade only)
