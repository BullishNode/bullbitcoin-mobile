# Keychain Manifest Architecture

## Scope

`keychain_manifest` records durable local metadata for app-created BIP85
materializations. It records reserved BIP85 derivations and typed
materializations of those derivations. Wallet materializations are the first
supported materialization type, with BTCPay as the first writer. It never stores
mnemonic words, seeds, private keys, or descriptors.

Manifest entries are durable local inventory, not product/server state. Once a
wallet materialization has been created and recorded, product failures such as
remote rejection, settings/default application failure, or connection-state
persistence failure keep the manifest entry. This PR intentionally treats the
manifest as local retry/recovery metadata and inventory, not product rollback
state. Later retries of the same record operation may idempotently add missing
proven entries, but this PR does not implement a separate repair API or flow.
Multi-wallet record calls are atomic: all wallet materializations for the call
are committed together, or none are committed. A later retry may idempotently
skip already-recorded identical rows and add missing proven materializations,
but no caller should observe a half-recorded batch from one failed call.

It can build an on-demand manifest file payload from local records for a
requested parent fingerprint. The local Drift records remain the source of
truth; the file payload is a read-only projection and is not cached as product
state. It can also validate an imported v1 payload into typed import intents for
later consumer flows. Import parsing does not persist, delete, create wallets,
publish, fetch, or restore product state, and non-wallet materialization types
are out of scope for v1.

V1 local recording accepts manifest-enabled registry-owned wallet-seed
reservations, because manifest inventory is generic metadata for app-created
BIP85 materializations. V1 file export/import/recovery currently supports the
BTCPay and Lightning Address wallet seed reservations. Lightning Address local
wallet materializations are recoverable, but the owning Lightning Address flow
must reactivate or verify Bullnym server state after recovery. Other reserved
wallet-seed paths may be recorded only after their owning runtime flow explicitly
adds manifest support; until then, they are omitted from v1 file payloads and
must not be presented as importable or recoverable.

## Boundaries

- `keychain_manifest` owns local keychain manifest entries, typed
  materializations, and persistence.
- `bip85_registry` owns reserved path policy.
- Product features, such as BTCPay, record entries through
  `keychain_manifest/public` only.
- The public boundary records wallet materializations only. Product features do
  not receive inserted-row rollback tokens or a public delete API for
  current-attempt rollback.
- The public boundary may build a manifest file payload, but file operations
  must not mutate local manifest inventory.
- `keychain_manifest` owns the remote manifest Nostr event schema and encrypted
  snapshot payload shape as a contract over the existing v1 manifest file
  projection.
- `keychain_manifest` must not import BTCPay, Get Paid, external receive
  wallets, keychain recovery, core Nostr relay/signing infrastructure, or UI
  features.

## Entry Identity

Keychain entries are generic at the reserved-path identity level and are
identified by:

- parent fingerprint
- registry-relative BIP85 path

Wallet materializations attach wallet-specific metadata to a keychain entry and
are identified by:

- wallet id

The child seed fingerprint is stored on each wallet materialization, because it
is wallet materialization metadata. Non-wallet BIP85 entries must not need a
dummy seed fingerprint.

## Manifest File

The manifest file is a serialized projection generated from local
`keychain_manifest` records. It is not the current-device source of truth, is
not maintained as a separate local file, and does not create wallets. Validated
import plans may be consumed by `keychain_recovery`, which owns local wallet
restore semantics.

Current-device source of truth:

- `bip85_registry` defines reserved paths and purposes.
- `keychain_manifest` database records define which app-created BIP85 material
  has been recorded for recovery/retry inventory.
- The manifest file payload is the latest compatible v1 projection of those
  records at the moment a caller builds it. Unsupported local reservations remain
  in Drift inventory but are omitted from v1 payloads until their owning flows
  add file/recovery support.
- The payload does not prove that every recorded wallet still exists locally.
  A future consumer that needs current wallet-existence guarantees must join
  against wallet inventory and define missing-wallet behavior explicitly.

The v1 file is deterministic JSON with this shape:

```json
{
  "version": 1,
  "parentFingerprint": "fedcba98",
  "generatedAt": 20,
  "inventoryUpdatedAt": 12,
  "entries": [
    {
      "entryId": "fedcba98:39'/0'/12'/100'",
      "bip85DerivationPath": "39'/0'/12'/100'",
      "reservationId": "btcpay_wallet_seed",
      "entryType": "walletSeed",
      "ownerFeature": "btcpay",
      "bip85Application": 39,
      "bip85Index": 100,
      "createdAt": 10,
      "updatedAt": 12,
      "materializations": [
        {
          "type": "wallet",
          "walletId": "btc-wallet",
          "childSeedFingerprint": "0123abcd",
          "network": "bitcoinMainnet",
          "walletPurpose": "bitcoin",
          "scriptType": "bip84",
          "createdAt": 10,
          "updatedAt": 10
        }
      ]
    }
  ]
}
```

Rules:

- `version` must be `1`.
- Fingerprints must be normalized 8-character lowercase hex values.
- `bip85DerivationPath` is the registry-relative hardened path.
- `entryId` is derived from parent fingerprint and BIP85 path.
- `inventoryUpdatedAt` is the latest timestamp among included entries and
  materializations. Empty manifests use the build timestamp. V1 decode rejects
  payloads whose `inventoryUpdatedAt` does not match that derived value.
- V1 supports only wallet materializations with `"type": "wallet"`.
- Public callers must explicitly opt in before exporting an empty manifest.
- V1 decode validates the payload wire shape in `data/`, then validates registry
  metadata into import intents in `domain/usecases`. Public import parsing
  requires the caller's expected parent fingerprint and rejects files from a
  different wallet before returning a plan. Wallet creation and restore semantics
  belong to `keychain_recovery`.
- V1 decode rejects duplicate entry ids and duplicate wallet materialization ids
  before recovery can perform wallet side effects.

The payload is generated on demand by callers that need a serialized projection.
Transport, wallet creation, product restore, and UI flows are out of scope and
are not specified by this feature.

## Nostr Event Contract

The Nostr remote manifest event schema is a transport contract over the existing
v1 manifest file payload. The local Drift records remain the source of truth;
the Nostr payload is a full replacement snapshot generated from those records.
NIP-01 event id calculation, event serialization, and relay message parsing use
the app's `nostr` package dependency where it provides those generic protocol
primitives. Manifest semantics remain owned here.

Public event metadata is intentionally minimal:

- event kind: `30078`
- addressable tag: `["d", "manifest"]`
- author: the dedicated wallet manifest Nostr role at `9000'/1'/1'`

Schema/version metadata lives inside the encrypted content as
`bullbitcoin.keychain_manifest.v1`; it must not be published as public Nostr
tags. The event draft carries opaque encrypted content only.

The remote manifest snapshot content is encrypted with a RecoverBull-style
encrypted backup envelope using a dedicated seed-derived BIP85 key at
`1642'/0'/1'`. This key is separate from RecoverBull vault backup keys at app
`1608` and separate from Nostr signing keys at app `9000`. The encryption use
case derives it from a caller-supplied root xprv and validates that the xprv
fingerprint matches the manifest parent fingerprint before encryption; the later
publish orchestration slice owns default-wallet xprv selection. The stable
`1642'/0'/1'` path is reserved in `bip85_registry` so restore can derive the
decrypt key from the seed without publishing derivation-path metadata as a Nostr
tag.

The signed-event slice signs the event with the wallet manifest Nostr role
through `nostr_identity` and stops at a locally built signed event. It does not
choose relays or perform transport work.

The relay transport slice is owned by `keychain_manifest` and talks only to
caller-supplied `wss` relay URLs. It uses concrete websocket relay transport
behind a manifest-specific repository and `nostr` package message parsing for
relay command results; it must not grow into a generic Nostr relay facade, event
bus, relay registry, public identity publisher, or reusable Nostr platform layer
without a second real caller. Publish success requires at least one relay `OK`
acceptance for the event id. Fetch accepts only authentic wallet-manifest events
for the derived manifest author, kind `30078`, and `d=manifest`, then returns
candidate events newest-first. Individual relay failures and malformed relay
events are collapsed into sanitized outcomes, and raw websocket errors must not
cross the public boundary. Local wallet creation and manifest recording must not
depend on relay publish or fetch success.

The Nostr import-plan slice derives the wallet-manifest author and encryption
key from the caller-supplied root xprv, fetches candidate relay events,
decrypts/parses newest-first, and returns a typed result: latest recoverable, no
manifest found, relays unavailable, no recoverable manifest, or newest failed
with an older recoverable candidate. It stops at `KeychainManifestImportPlan`;
wallet restore, product reactivation, relay-disclosure UX, and UI are separate
feature slices.

The wallet manifest Nostr role must not be reused for Bullnym server
authentication, NIP-05, profile publishing, DMs, or any public identity flow.
