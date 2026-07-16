# BIP85 Registry Architecture

The BIP85 registry owns static reservations for derivation paths reserved by
first-party features. It is policy, not runtime state: it does not record
created secrets, wallets, recovery-manifest entries, or allocation history.

## Boundaries

- `domain/` defines immutable reservation metadata and the static entries.
- `public/` exposes read-only lookup and exclusion helpers.
- The composition root may register the stateless facade for consumers.
- The registry owns no database, repository, datasource, UI, allocator, or
  runtime manifest writer.
- Reservation metadata includes the canonical deterministic alias used when
  deriving or reusing the reserved BIP85 child. Product features and recovery
  use that alias through the registry instead of duplicating product constants.

## Reservation Shapes

Reservations come in exactly two typed shapes, enforced at construction:

- Wallet-seed reservations (`Bip85WalletSeedReservation`) materialize a BIP85
  child wallet seed. Their scope requires a hardened `index` segment and
  exposes it as a typed `walletIndex`; construction throws if the segment is
  missing.
- Key reservations (`Bip85KeyReservation`) reserve non-wallet key material.
  Their scope has no wallet index and construction throws if an `index`
  segment is supplied, so a key reservation cannot even be asked for a wallet
  index.

Both shapes derive their exact path from the application number and the ordered
path segments; the path string is never stored separately.

## Current Reservations

BTCPay reserves BIP85 path `39'/0'/12'/100'`: a BIP39 English 12-word child
mnemonic at child index `100`. The registry is the source of truth for this
path. The interim development index `77` was never released and has no
migration or compatibility behavior.

Lightning Address reserves BIP85 path `39'/0'/12'/101'`, which is a BIP39
English 12-word child mnemonic at child index `101`.

Payment Page reserves BIP85 path `39'/0'/12'/102'`, which is a BIP39 English
12-word child mnemonic at child index `102`.

Nostr role keys reserve the app-owned Nostr namespace paths under the current
bitcoin/bips#2126 proposal. This rewrite reviewed PR #2126 at commit
`e6df9dbf1093444302331565a1a8f58144175a21`; re-check that pin immediately
before publishing the rewritten stack.

- `128002'/100'/1'` for unified Bull backup signing.
- `128002'/101'/1'` for Bullnym server authentication.
- `128002'/102'/1'` for NIP-05 public nym verification.

The application-owned identity range is `100'` through `199'`. The three
assigned roles are `100'` unified Bull backup signing, `101'` Bullnym
authentication, and `102'` NIP-05 public verification. User-created identities
must not use the reserved range.

These Nostr-compatible reservations are static namespace policy only. They do
not require Nostr events or relays. The wallet-backup role signs Bullnym backup
requests; the other roles retain their existing product responsibilities.
The exact app number and role segments are the locked namespace allocation;
later Nostr behavior work may consume these ids and paths, but should not infer
runtime semantics from this registry entry alone.

Wallet Backup reserves BIP85 path `1642'/0'/1'` as the encryption key for the
unified Bull backup envelope. This is a Bull-owned custom application namespace
and must not be reused for RecoverBull vault backups, Nostr signing, Bullnym
authentication, or wallet-seed materialization. `wallet_backup` owns encryption
and encrypted-envelope semantics; the registry only blocks and names the path.

Future reservations should add typed entries here only when a first-party
feature needs a stable, blocked path. User-created ad hoc BIP85 outputs remain
outside this registry unless they become a first-party reserved namespace.

## Reservations Outside This Registry

Ark and RecoverBull hold BIP85 reservations outside this registry (Ark at hex
application index `11811`; RecoverBull at application `1608'`). Before any
manual or custom allocation feature is built on top of this registry, a
collision audit against those external reservations is required.
