# Wallet Backup Architecture

## Scope

`wallet_backup` owns the seed-bound encrypted Bull backup container and its single opaque Bullnym remote object.
This slice includes the outer envelope, the manifest section adapter, authenticated encryption, BIP85 encryption-key derivation, unified Nostr request signer, remote repository, and conditional manifest publication.
This slice also owns one durable `WalletBackupState` row for the unified lifecycle.
Lifecycle controls, scheduling, and recovery orchestration are added by their later owning PRs.

This is one backup lifecycle, not a wrapper around separate manifest and
metadata backup systems. `keychain_manifest` remains the source of truth for
local derivation inventory and owns its canonical payload. `wallet_backup`
consumes that payload only through `keychain_manifest/public`.

## Envelope

The current canonical plaintext is:

```json
{
  "version": 1,
  "contentType": "bullbitcoin.wallet_backup.v1",
  "parentFingerprint": "fedcba98",
  "createdAt": 1751328000,
  "sections": {
    "keychain_manifest": {
      "version": 1,
      "payload": {}
    }
  }
}
```

`payload` is the canonical `bullbitcoin.keychain_manifest.v1` object produced
by `KeychainManifestFacade.buildManifestFilePayload`. It is embedded as JSON,
not as an escaped JSON string.

At this point in the stack, `keychain_manifest` is the only supported section.
An unknown section or unsupported section version is a write-blocking failure;
an older client must never overwrite data it cannot understand. The metadata
owning PR extends this fixed v1 section set with `wallet_metadata`; it does not
introduce a generic section registry.

Canonical form is fixed key order with no insignificant whitespace. Decode
rejects a non-canonical outer structure, missing or unknown outer fields,
invalid fingerprints, unsupported versions, and disagreement between the
outer and manifest parent fingerprints. The caller supplies the expected
active-seed fingerprint during decrypt, and a mismatch is a distinct typed
failure.

The manifest owner deliberately accepts unknown v1 manifest fields on read.
An authenticated manifest section that is valid but cannot be reproduced in
the owner's canonical form remains available for recovery with
`isCanonical == false`. Encryption/publication refuses such a section, so an
older client can recover known records without overwriting fields it cannot
preserve.

## Cryptography and Bounds

The encryption key is deterministically derived at BIP85 path
`1642'/0'/1'`, reserved as `wallet_backup_encryption_key`. No encryption key or
plaintext private material is persisted.

Ciphertext uses the existing RecoverBull-compatible authenticated format:

```text
base64(nonce16 || AES-256-CBC ciphertext || HMAC-SHA256)
```

Bullnym accepts at most 2 MiB of decoded ciphertext. The envelope enforces a
pre-encryption aggregate plaintext limit of `2 MiB - 64 bytes`, leaving room
for the nonce, maximum CBC padding, and HMAC. The existing section-specific
record and nesting limits still apply. Chunking is out of scope.

## Dependencies

```text
wallet_backup
  -> keychain_manifest/public
  -> bip85_registry/public
  -> nostr_identity/public
  -> bullnym/public
```

`keychain_manifest` never imports `wallet_backup`. The generic authenticated
cipher stays in `core/backup` because it is provider-neutral infrastructure;
the adapter that maps it to wallet-backup entities and failures belongs here.

## Remote Publication

The remote repository maps only the closed Bullnym `wallet_backup` stream into wallet-backup domain heads and typed failures.
The signer is derived on demand at `128002'/100'/1'`; the private key is never persisted or exposed by this feature.

Publication builds the current local manifest, fetches the remote head, authenticates and decrypts a present envelope, delegates manifest validation and merge behavior to `keychain_manifest/public`, and conditionally stores one new encrypted envelope.
A remote manifest that is valid for recovery but is not canonical blocks publication so an older writer cannot erase fields it cannot preserve.

A head conflict causes exactly one refetch, re-merge, re-encrypt, and retry.
A second conflict returns a typed failure.
If the merged manifest already equals the authenticated remote manifest, no write occurs and the existing canonical content hash and checkpoint are returned.

## Durable State

Schema 16 introduces exactly one singleton `wallet_backup_states` table.
It records enablement, dirty state and its monotonic revision, attempt and success timestamps, the last verified remote generation/ETag/content hash, and a newer unsupported outer-envelope version that blocks publication.
The state repository preserves dirty work when a store that captured an older revision succeeds.
Disabling does not clear dirty work or delete the remote object, and clearing a confirmed remote checkpoint does not change enablement.
Section owners do not write this table directly; later lifecycle and coordinator PRs connect their committed public change signals to `wallet_backup`.

## Non-goals in This Slice

- automated publication coordination
- settings or onboarding UI
- metadata payload semantics
- compatibility with pre-release backup streams or encryption reservations
