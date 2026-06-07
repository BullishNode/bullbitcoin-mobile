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

## Current Reservation

BTCPay reserves BIP85 path `39'/0'/12'/100'`, which is a BIP39 English
12-word child mnemonic at child index `100`.

Future reservations should add typed entries here only when a first-party
feature needs a stable, blocked path. User-created ad hoc BIP85 outputs remain
outside this registry unless they become a first-party reserved namespace.
