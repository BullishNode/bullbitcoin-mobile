# Wallet Metadata Backup Architecture

## Scope

`wallet_metadata_backup` owns the versioned `wallet_metadata` section, its
contributor registry, and recovery planning/apply. The wallet-backup feature
owns encryption, transport, durable state, scheduling, and lifecycle. Bullnym
is the only remote store. The wallet does not open relay WebSockets, construct
Nostr events, or expose relay policy here.

The keychain manifest and metadata remain separate owned sections inside the
single `wallet_backup` stream. They share one activation, signing identity,
encryption key, payload, and remote object. Metadata recovery never enables
future metadata uploads.

## Snapshot

Envelope version 1 is canonical compact UTF-8 JSON with these fields:

`contentType`, `envelopeVersion`, `parentFingerprint`, `revision`, `createdAt`,
`recordsHash`, `recordCount`, `sections`, and `records`.

Each record contains `type`, `version`, `scope`, `recordId`, and `payload`.
Object keys inside contributor data are sorted recursively; array order is
preserved. Records sort by their complete identity. Decoding re-encodes and
requires byte-for-byte equality. Section and aggregate SHA-256 hashes bind the
complete canonical record sets.

There are no roots, chunks, event ids, tags, relay observations, replica counts,
or transport timestamps. One update is one authenticated ciphertext blob. The
decoded ciphertext limit is 2 MiB, one record is limited to 64 KiB, nesting is
limited to 32, and the logical record cap is 5,000. A representative 1,000-label
fixture is required to stay below the blob limit.

Unknown record types and positive versions remain opaque structured JSON. A
supported contributor replaces only the projection it owns; composition keeps
unknown remote records and section declarations.

## Cryptography

The unified backup signing identity remains frozen at BIP85 path
`128002'/100'/1'`. The encryption key remains frozen at `1642'/0'/1'`. The
Bullnym auth and NIP-05 identities remain separate app-reserved roles.

Plaintext is encrypted using the RecoverBull-compatible authenticated format:

`base64(nonce16 || AES-256-CBC ciphertext || HMAC-SHA256)`.

The feature supplies a short-lived signing capability to the Bullnym public
facade. Bullnym receives the stream public key, signed request data, and opaque
ciphertext, never the xprv, encryption key, fingerprint, records, or labels.

## Remote Boundary

`WalletMetadataBackupSectionProvider` maps contributor exports and recovery to
the outer wallet-backup envelope. HTTP, JSON, base64 request mapping, signed
request layout, encryption, and status-code mapping stay in
`features/wallet_backup` and `features/bullnym`. There is no metadata-owned
remote repository, signer, encryption key, or wire client.

## Local State

The unified wallet-backup state stores one row with:

- activation;
- `dirty` plus monotonic `dirtyRevision`;
- last attempt and success timestamps;
- verified Bullnym generation, ETag, snapshot revision, and content hash;
- an unsupported-newer-envelope block;
- a recovery-apply block.

Activation itself is the explicit storage choice; there is no metadata-specific
consent or checkpoint. Enabling marks the unified backup dirty. Disabling
stops future stores but preserves dirty work and the checkpoint. Explicit
deletion is performed once by the wallet-backup coordinator and conditionally
deletes the exact current generation and ETag.

Every mutation increments `dirtyRevision`, even while already dirty. A store may
clear dirty work only when the captured revision still matches. Mutations that
arrive during encryption or HTTP work therefore remain pending.

## Publication

The wallet-backup coordinator performs these steps:

1. Require enabled, dirty, and no version/recovery block.
2. Capture the dirty revision and export the manifest and every metadata
   contributor.
3. Fetch the current Bullnym object.
4. Authenticate, bound, decrypt, parse, and validate it when present.
5. Refuse to overwrite malformed, undecryptable, or newer-version data.
6. Compose both owned sections over compatible remote unknown data.
7. Skip the store when canonical content is unchanged.
8. Encrypt one complete snapshot and conditionally store generation plus one.
9. Persist the receipt and clear only the captured dirty revision.
10. On conflict, refetch and recompose once; a second conflict remains dirty.

An initially empty inventory creates no object. Once an object exists, an
intentional later empty inventory is a valid replacement.

Manifest and metadata post-commit streams mark the one durable wallet-backup
state dirty and arm one debounced delayed fallback. A successful foreground
wallet sync is the normal flush trigger, and `Back up now` bypasses the wait.
Only one store may be in flight.

## Recovery

Recovery is automatic after keychain recovery has determined which wallets
exist. The already-fetched, authenticated wallet-backup envelope supplies the
metadata section to the section provider, which validates it and builds a
recovery plan.
Bullnym absence or network failure never blocks seed recovery.

Apply revalidates every planned intent against the authenticated snapshot before
writing. The recovery orchestrator captures the authenticated unified remote
head before any local writes and refetches it afterward; it leaves publication
blocked unless generation, ETag, presence, and ciphertext hash are unchanged.
Labels restore additively, freezes only add frozen outpoints, and wallet
preferences overwrite defaults only for wallets created in this recovery run.
Existing local choices are preserved and absent wallet references are deferred.

Publication suppression spans keychain materialization through metadata apply.
The durable suppression flag is written before materialization starts, survives
process termination, and is cleared only after complete remote revalidation.
Apply does not enable backup and does not publish. Unsupported, invalid,
deferred, conflicting, or failed work is reported without creating a second
metadata lifecycle or remote mutation.

## Contributors

- `labels.bip329` stores complete BIP329 annotation objects and restores by the
  portable labels-owned identity. It never carries `spendable` freeze state.
- `wallet.utxo_freeze` stores exact wallet attribution plus outpoint and only
  restores `frozen:true`. Unattributed records remain unattributed.
- `wallet.preferences` stores only `label`, `hideOnHome`, and
  `autoSweepEnabled`, preserving explicit false/empty values and omitting nulls.

Future metadata adds another versioned contributor to this snapshot. It does
not add another endpoint, key, blob, or scheduler.

## Boundaries

- `bip85_registry` owns frozen derivation reservations.
- `nostr_identity` owns role-named BIP340 derivation and signing capability;
  this does not imply relay use.
- `bullnym/public` owns the shared opaque blob HTTP contract after integration.
- Contributors use only owner repositories/use cases or public facades.
- Other features import only `wallet_metadata_backup/public`.
- Backup Settings and Remote Keychain Recovery wrap facade calls in their own
  use cases; presentation never imports metadata internals.
