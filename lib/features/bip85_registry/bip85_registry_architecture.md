# BIP85 Registry Architecture

The BIP85 registry owns static reservations for BIP85 derivation paths that the
application reserves for first-party features.

It is not runtime state. It does not record which secrets have been created,
which wallets exist, or which future recovery manifest entries should be
published. Those concerns stay with the creating feature, wallet metadata, and
the future keychain manifest.

## Boundaries

- `domain/` defines reservation metadata and static reservation entries.
- `public/` exposes read-only lookup helpers for other features.
- No database, dependency injection, UI, allocation service, or runtime manifest
  writer is owned here.

## Current Reservation

BTCPay reserves BIP85 path `39'/0'/12'/100'`, which is a BIP39 English
12-word child mnemonic at child index `100`.

Child index `100` superseded an interim development value of `77` that was
used while the BTCPay pairing flow was being built and never shipped in a
release. The registry value is the locked source of truth for this path; no
migration from the interim value exists or is planned.

Future reservations should add typed entries here only when a first-party
feature needs a stable, blocked path. User-created ad hoc BIP85 outputs remain
outside this registry unless they become a first-party reserved namespace.

## Reservations Outside This Registry

The registry currently covers BTCPay only. Ark and RecoverBull hold BIP85
reservations outside this registry (Ark at hex application index `11811`;
RecoverBull at application `1608'`). Before any manual or custom allocation
feature is built on top of this registry, a collision audit against those
external reservations is required.
