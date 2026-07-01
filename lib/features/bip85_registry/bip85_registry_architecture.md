# BIP85 Registry Architecture

The BIP85 registry owns static reservations for BIP85 derivation paths that the
application reserves for first-party features.

It is not runtime state. It does not record which secrets have been created,
which wallets exist, or which manifest entries should be published. Those
concerns stay with the creating feature, wallet metadata, and
`keychain_manifest`.

## Boundaries

- `domain/` defines reservation metadata and static reservation entries.
- `public/` exposes read-only lookup helpers for other features.
- No database, dependency injection, UI, allocation service, or runtime manifest
  writer is owned here.
- Reservation metadata includes the canonical deterministic alias used when
  deriving or reusing the reserved BIP85 child. Product features and recovery
  use that alias through the registry instead of duplicating product constants.

## Current Reservations

BTCPay reserves BIP85 path `39'/0'/12'/100'`, which is a BIP39 English
12-word child mnemonic at child index `100`.

Lightning Address reserves BIP85 path `39'/0'/12'/101'`, which is a BIP39
English 12-word child mnemonic at child index `101`.

Payment Page reserves BIP85 path `39'/0'/12'/102'`, which is a BIP39 English
12-word child mnemonic at child index `102`.

Nostr role keys reserve the app-owned Nostr namespace paths:

- `9000'/1'/1'` for the future wallet manifest key.
- `9000'/2'/1'` for Bullnym server authentication.
- `9000'/3'/1'` for future NIP-05 public nym verification.

These Nostr reservations are static namespace policy only. They do not implement
Nostr signing, relay publish/fetch, wallet manifest transport, DMs, NIP-05
registration, verification, lookup, NIP-05 UI, or product behavior.
The exact app number and role segments are the locked PR7 namespace allocation;
later Nostr behavior PRs may consume these ids and paths, but should not infer
runtime semantics from this registry entry alone.

Keychain Manifest reserves BIP85 path `1642'/0'/1'` as the primary encryption key for remote manifest snapshot payloads.
This is a Bull-owned custom application namespace and must not be reused for RecoverBull vault backups, Nostr signing, Bullnym authentication, or wallet-seed materialization.
`keychain_manifest` owns encryption and encrypted payload semantics; the registry only blocks and names the path.

Future reservations should add typed entries here only when a first-party
feature needs a stable, blocked path. User-created ad hoc BIP85 outputs remain
outside this registry unless they become a first-party reserved namespace.
