# Get Paid Settings Architecture

## Scope

`get_paid_settings` owns the persisted **automated backup preference** for the
Get Paid deterministic wallets (the toggle + the one-time disclosure
acknowledgement, decisions [3]/[A]), the **blocking consent dialog** and its
locked copy, the **Get Paid settings screen** and hub entry, and — critically —
the **single production caller** of the encrypted-Nostr-snapshot publish
(`PublishAutomatedKeychainBackupUsecase`, §3.2). Every consent/empty/xprv gate
that protects a network publish lives in that one chokepoint.

It does not own encryption, signing, or relay transport (that is
`keychain_manifest`), recovery orchestration (`remote_keychain_recovery`), the
relay list or its consent-gate semantics (`nostr_relay_policy`), or product
activation (`btcpay` / `lightning_address`). It records nothing to the manifest
and never touches manifest crypto/codec internals.

The toggle gates the **network publish only**: wallet creation and the local
manifest record stay unconditional, so file-based recovery works with the
toggle off. The disclosure ack (not the toggle) gates any third-party-relay
contact — publish AND fetch — and is the same persisted value the recovery
fetch gate reads (R2-P21c).

The default-wallet xprv adapter derives byte-for-byte identically to
`RemoteKeychainRecoveryDefaultWalletXprvAdapter`; the published author key must
equal the key recovery fetches under (KC-4 obligation 4). The two adapters are
intentionally not consolidated in PR23 — a parity test pins the equivalence.

## Boundaries

Allowed dependencies:

- `get_paid_settings -> keychain_manifest/public` (publish the snapshot)
- `get_paid_settings -> nostr_relay_policy/public` (read the relay policy)
- `get_paid_settings -> core/storage` (drift persistence)
- `get_paid_settings -> core/wallet` (default wallet lookup for the xprv adapter)
- `get_paid_settings -> core/seed` (seed → xprv derivation)
- `get_paid_settings -> core/settings` (environment for the wallet lookup)

Forbidden dependencies:

- `get_paid_settings -> btcpay | lightning_address | remote_keychain_recovery`
  (consumption is one-directional: those features depend on this one)
- `get_paid_settings -> keychain_manifest/domain | keychain_manifest/data`
  (the crypto/codec/fetch core is consumed only through the facade)

## Contract semantics

- The publish is **post-commitment best-effort** (AD-3): it runs after the
  durable manifest record and never rethrows into the creation/restore flow.
- The publish is **structurally unable** to emit an empty NIP-33 event: the
  facade method exposes no `allowEmpty` parameter, and an empty inventory
  surfaces as a logged skip.
- Consent is shown once and persisted; the same acknowledgement is honoured by
  both wallet creation and remote recovery.
