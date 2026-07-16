# Wallet Backup Rearchitecture: Bullnym Opaque Blob Storage

## Status

Draft target architecture for the unmerged wallet backup PR stack.

This document replaces the Nostr-relay transport design for both the keychain
manifest and wallet metadata. The local manifest, metadata records, BIP85 key
reservations, encryption, recovery rules, and independent product controls
remain. Bullnym becomes the only remote storage service.

## Locked Decisions

1. The wallet does not connect to Nostr relays to publish or recover backups.
2. Bullnym stores one current opaque encrypted blob for each backup stream.
3. The keychain manifest and wallet metadata remain separate streams with
   separate activation, signing identities, encryption keys, state, and
   failure handling.
4. Existing deterministic derivations remain frozen:
   - keychain signing identity: `9000'/1'/1'`;
   - keychain encryption key: `1642'/0'/1'`;
   - wallet metadata signing identity: `9000'/4'/1'`;
   - wallet metadata encryption key: `1642'/0'/2'`.
5. Neither stream reuses the generic Bullnym identity at `9000'/2'/1'`.
6. Bullnym identifies and authorizes a stream by its stream-specific x-only
   public key and BIP340 signatures. There is no Bullnym account or registration
   dependency.
7. Bullnym never receives plaintext, an xprv, an encryption key, a wallet
   fingerprint, a label, a wallet reference, or a Nostr event.
8. There is no chunk protocol. One stream update is one HTTP store request and
   one database object.
9. Metadata changes become durable dirty work immediately, but automatic
   upload runs after a successful foreground wallet sync. `Back up now` remains
   available.
10. Keychain-manifest changes upload promptly after the local manifest entry is
    committed. Failed work remains dirty and retries at startup, resume, and
    successful sync.
11. Recovery checks Bullnym automatically after seed recovery. It does not ask
    for relay disclosure or enable future uploads.
12. Remote-backup failure never blocks seed recovery. These backups are a
    convenience layer, not fund-recovery authority.
13. Metadata is applied only after keychain recovery has decided which wallets
    exist. Metadata cannot create or infer wallets.
14. The initial decoded-ciphertext limit is 2 MiB per stream. The JSON HTTP body
    limit is 3 MiB to accommodate base64 and request fields. A release fixture
    containing 1,000 representative labels must fit before launch.
15. Bullnym stores only the current object, not user-visible history. Normal
    database backups remain an operations concern, not part of the wallet
    protocol.

## Product Boundary

The two streams solve different problems:

| Stream | Restores | Does not restore |
| --- | --- | --- |
| Keychain manifest | Which deterministic product wallets were materialized and the derivation evidence needed to recreate them | Funds, arbitrary imported wallets, labels, settings |
| Wallet metadata | BIP329 labels, frozen UTXO state, and approved wallet preferences | Wallet key material, descriptors, balances, transactions, product activation |

The keychain manifest remains optional because the app can derive every
reserved wallet through an explicit discovery action. Metadata remains optional
because losing labels and preferences does not lose funds.

Future wallet metadata is added as another versioned record contributor inside
the wallet-metadata plaintext. It does not require a new Bullnym endpoint,
remote object, signing identity, encryption key, or activation control.

## Threat and Privacy Model

Bullnym can observe:

- the source IP address or trusted-proxy source identity;
- the stream type;
- one pseudonymous stream public key;
- request time, frequency, response status, and ciphertext size.

Bullnym cannot read or forge valid backup plaintext because encryption and
authentication happen in the wallet with a separate seed-derived encryption
key. Separate stream identities prevent a database join by public key. Bullnym
can still correlate streams probabilistically through IP address, timing, and
size. V1 does not add padding, batching, Tor, or delayed uploads.

TLS protects requests in transit. The application trusts Bullnym for
availability and current-object selection, but not for plaintext integrity.
Authenticated encryption must reject modified or cross-stream ciphertext.
Because this is a convenience service, V1 does not attempt relay-style
censorship resistance or remote rollback proofs.

## Bullnym HTTP Contract

### Endpoints

All identifiers are carried in authenticated JSON bodies rather than URLs or
query strings so normal access logs do not contain stream public keys.

- `POST /api/v1/wallet-backups/fetch`
- `PUT /api/v1/wallet-backups`
- `DELETE /api/v1/wallet-backups`

Valid stream values are `keychain_manifest` and `wallet_metadata`.

### Signed Message

Every request uses the caller-provided stream signer and the existing Bullnym
convention of signing the SHA-256 digest of a fixed NUL-separated byte string.
The new domain is independent of `bullpay-la-v2`:

```text
bullbitcoin-wallet-backup-v1\0<action>\0<stream>\0<npub_hex>\0<generation>\0<expected_etag_or_empty>\0<ciphertext_sha256_or_empty>\0<ciphertext_bytes>\0<timestamp>
```

That is one continuous byte sequence. The display contains no spaces or line
breaks beyond bytes present in field values, and field values cannot contain
NUL.

`action` is exactly `backup-fetch`, `backup-store`, or `backup-delete`.
`npub_hex` is a canonical lowercase 32-byte x-only public key. Numeric fields
are unsigned base-10 integers without leading zeros. The timestamp freshness
window remains 300 seconds.

The signature binds the operation, stream, identity, optimistic-concurrency
head, payload hash, payload size, and request time. It does not sign arbitrary
JSON serialization.

### Fetch

Request:

```json
{
  "version": 1,
  "stream": "wallet_metadata",
  "npub": "<64 lowercase hex>",
  "timestamp": 0,
  "signature": "<128 lowercase hex>"
}
```

For fetch signatures, `generation`, ETag, hash, and byte count in the signed
message are `0`, empty, empty, and `0` respectively.

Response when an object exists:

```json
{
  "version": 1,
  "found": true,
  "generation": 7,
  "etag": "<64 lowercase hex>",
  "ciphertext": "<canonical base64>",
  "ciphertext_sha256": "<64 lowercase hex>",
  "ciphertext_bytes": 183421,
  "updated_at": 0
}
```

Response for a new identity:

```json
{
  "version": 1,
  "found": false,
  "generation": 0,
  "etag": null
}
```

A recently deleted object may return `found:false` with a non-zero generation
and non-null ETag. This is a short-lived tombstone used only for replay-safe
replacement.

### Store

Request:

```json
{
  "version": 1,
  "stream": "wallet_metadata",
  "npub": "<64 lowercase hex>",
  "generation": 8,
  "expected_etag": "<previous ETag or null>",
  "ciphertext": "<canonical base64>",
  "ciphertext_sha256": "<64 lowercase hex>",
  "ciphertext_bytes": 184002,
  "timestamp": 0,
  "signature": "<128 lowercase hex>"
}
```

The server performs these checks in order:

1. Apply cheap body-size and source-rate gates.
2. Parse only the exact V1 request shape and bounded fields.
3. Decode canonical base64 and verify byte count and SHA-256.
4. Verify timestamp and BIP340 signature.
5. Lock `(stream, npub)` in one database transaction.
6. Return success for an exact retry of the current generation and ciphertext.
7. Otherwise require `expected_etag` to match the current head and generation to
   equal current generation plus one.
8. Replace the current ciphertext and return the new head.

The ETag is deterministic:

```text
SHA256("bullbitcoin-wallet-backup-etag-v1\0" || stream || "\0" ||
       npub || "\0" || generation_decimal || "\0" || ciphertext_sha256)
```

A stale conditional store returns HTTP 409 with code
`BackupHeadConflict`. It does not return another object's contents. HTTP 413 is
`BackupBlobTooLarge`; 429 is `RateLimited`; malformed requests are 400;
signature or timestamp failures are 401.

### Delete

Delete signs the next generation and the current expected ETag with empty hash
and zero bytes. Deletion is conditional: it cannot delete a blob written after
the wallet's last fetch.

The transaction erases the ciphertext and writes a tombstone head. The
tombstone contains only stream, public key, generation, ETag, and deletion time.
It expires after ten minutes, which is longer than the request-authentication
window. Therefore a captured initial store request cannot recreate a deleted
blob after the row disappears.

When fetch returns generation zero and no ETag, the client treats deletion as
already complete and sends no delete request. Repeating a delete against its
current tombstone is idempotent. Any other head mismatch returns 409 and
requires a fresh fetch before the user can retry.

## Bullnym Server Design

### Database

Use the next available migration, currently expected to be
`043_wallet_backup_blobs.sql`:

```sql
CREATE TABLE wallet_backup_blobs (
    stream              TEXT        NOT NULL,
    author_pubkey       BYTEA       NOT NULL,
    generation          BIGINT      NOT NULL CHECK (generation > 0),
    etag                 BYTEA       NOT NULL,
    ciphertext          BYTEA,
    ciphertext_sha256   BYTEA,
    ciphertext_bytes    INTEGER,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at           TIMESTAMPTZ,
    PRIMARY KEY (stream, author_pubkey),
    CHECK (stream IN ('keychain_manifest', 'wallet_metadata')),
    CHECK (octet_length(author_pubkey) = 32),
    CHECK (octet_length(etag) = 32),
    CHECK ((ciphertext IS NULL) = (deleted_at IS NOT NULL)),
    CHECK (
      (ciphertext IS NULL AND ciphertext_sha256 IS NULL AND ciphertext_bytes IS NULL)
      OR
      (ciphertext IS NOT NULL AND ciphertext_sha256 IS NOT NULL AND ciphertext_bytes IS NOT NULL)
    ),
    CHECK (ciphertext_sha256 IS NULL OR octet_length(ciphertext_sha256) = 32),
    CHECK (ciphertext_bytes IS NULL OR ciphertext_bytes = octet_length(ciphertext)),
    CHECK (ciphertext_bytes IS NULL OR ciphertext_bytes <= 2097152)
);
```

Store decoded ciphertext bytes, not base64 and not parsed plaintext. The HTTP
layer encodes them on fetch. Validate stream values in Rust as a closed enum;
the database does not become a generic arbitrary-key object store.

The implementation belongs in a focused `src/wallet_backup.rs` handler/service
and narrow `db` functions. Reuse `auth::verify_signature`, source IP extraction,
`AppError`, Axum state, SQLx transactions, and existing response/error
conventions. Do not route backup rules through invoice, registration, donation
page, or Nostr modules.

### Abuse Controls

Launch defaults:

- 2 MiB decoded ciphertext per object;
- 3 MiB request-body limit on the store route;
- 120 fetch attempts per source per hour;
- 30 mutation attempts per source per hour;
- 20 mutations per authenticated stream key per hour;
- 10 distinct stream keys mutated per source per day;
- configurable global stored-byte ceiling; new stores return 503 when reached,
  while fetch and delete remain available.

These are operational defaults, not signed protocol constants except for the
2 MiB mobile compatibility limit. They need production metrics and can be
tuned without a mobile release.

Do not log request bodies, ciphertext, signatures, public keys, or ETags.
Metrics may include action, stream, status class, latency, and size bucket.
Error logging uses a one-way truncated identifier only when correlation is
needed for diagnosis.

### Availability

No special replication protocol or object-store dependency is required for
V1. Bullnym's PostgreSQL durability and ordinary encrypted database backups are
sufficient for a convenience service. A server outage leaves wallet work dirty
and recovery continues without metadata.

## Mobile Architecture

### Shared Bullnym Boundary

Extend the existing `features/bullnym` feature because it already owns the
Bullnym HTTP protocol and Dio client:

```text
features/bullnym/
  domain/
    bullnym_backup_blob.dart
    bullnym_backup_actions.dart
    usecases/fetch_bullnym_backup_usecase.dart
    usecases/store_bullnym_backup_usecase.dart
    usecases/delete_bullnym_backup_usecase.dart
  data/
    bullnym_http_client.dart
  public/
    bullnym_facade.dart
```

Add typed methods to `BullnymClientPort` and `BullnymFacade`. Product features
consume only the public facade and typed `Result` values. Dio, request JSON,
base64, HTTP status mapping, and the signed-message layout stay inside Bullnym.

The Bullnym API accepts a `BullnymAuthSigner` capability. Keychain and metadata
derive their own role-specific short-lived signers and adapt them to this
capability. Bullnym never derives keys and never receives an xprv.

Do not create a second HTTP stack, a generic provider/plugin system, an S3
adapter, or a new cross-feature `port/adapter/application/framework` hierarchy.

### Shared Encryption Primitive

Move and rename `core/nostr/nostr_authenticated_cipher.dart` to a
provider-neutral backup/crypto name. Preserve its RecoverBull-compatible bare
authenticated ciphertext format:

```text
base64(nonce16 || AES-256-CBC ciphertext || HMAC-SHA256)
```

The keychain and metadata repositories wrap this primitive with their own key
types and error families. The stream encryption keys remain separate. This is
only shared cryptographic machinery; it does not merge the two backup domains.

`core/nostr/nostr_signed_event.dart` and `nostr_relay_transport.dart` are removed
when no non-backup caller remains. Nostr identity/BIP340 derivation and Bullpay
signing remain because they serve non-relay features.

### Keychain Manifest

Preserve:

- the local manifest entry table and record-on-materialization behavior;
- reservation support rules and derivation evidence;
- canonical manifest file build/parse;
- import planning, conflict detection, and wallet materialization;
- the existing BIP85 signing and encryption reservations.

Replace Nostr-specific entities and use cases with provider-neutral backup
names. The encrypted plaintext remains a strict versioned wrapper around the
canonical manifest file. Keep its current wire shape where the fields are not
Nostr-specific to avoid gratuitous format churn.

The feature owns a durable local backup state instead of relying only on the
Get Paid settings row:

- `enabled`;
- `dirty` and monotonic `dirtyRevision`;
- `lastAttemptedAt` and `lastSucceededAt`;
- last verified Bullnym generation and ETag;
- last verified manifest content hash;
- an unsupported-newer-version block.

Recording a materialized manifest entry marks this stream dirty in the same
local transaction. The post-commit flow attempts an immediate best-effort
upload. Startup, resume, and successful wallet sync retry dirty work. Empty
local manifest state never overwrites a populated remote manifest.

Before store, fetch and decrypt the current remote manifest. Merge compatible
remote entries with local entries using the existing manifest identity and
conflict rules, then conditionally store the result. This prevents another
device from being silently erased. An unsupported newer manifest blocks writes
until the app understands it.

The Get Paid toggle and consent UI call the keychain-manifest facade; Get Paid
no longer owns publication transport or relay policy.

### Wallet Metadata

Preserve:

- the generic versioned record envelope;
- canonical JSON, strict parsing, bounds, section hashes, and aggregate hash;
- unknown type/version preservation during composition;
- the BIP329 labels, UTXO-freeze, and wallet-preferences contributors;
- additive labels, freeze-only restore, and ownership-aware preference restore;
- durable dirty revisions and recovery-apply suppression;
- the existing metadata BIP85 reservations.

Replace the root/chunk graph with one encrypted snapshot:

```text
WalletMetadataSnapshot
  envelopeVersion
  contentType
  parentFingerprint
  snapshotRevision
  createdAt
  sections[]
  recordCount
  recordsHash
  records[]
```

The fingerprint and all records are inside authenticated encryption. There are
no chunk references, event IDs, `d` tags, relay observations, EOSE states,
replica counts, event timestamps, or signed frame sizes.

The snapshot codec keeps strict canonical encoding and a 2 MiB decoded
ciphertext bound. Logical record and nesting limits remain defense-in-depth,
but the current 50,000-record/12-MiB/128-chunk transport limits are removed or
replaced by limits consistent with one 2 MiB object.

Publication becomes:

1. Check `enabled`, `dirty`, and local recovery/version blocks.
2. Capture `dirtyRevision`.
3. Export every registered contributor; any owner failure aborts the attempt.
4. Fetch the current Bullnym blob for the metadata stream.
5. Verify bounds, decrypt, parse, and validate it when present.
6. Block rather than overwrite a malformed, undecryptable, or newer-version
   current blob.
7. Compose supported local records over the compatible remote snapshot while
   preserving unknown types and versions.
8. If canonical content is unchanged, record the fetched head and clear only
   the captured dirty revision.
9. Otherwise encrypt one snapshot and conditionally store it.
10. On success, persist the new ETag/generation/content hash and clear dirty
    only if no mutation arrived during the request.
11. On 409, refetch and retry composition once. A second conflict leaves work
    dirty for the next trigger.

An initially empty inventory creates no remote object. Once a verified remote
snapshot exists, a later intentionally empty metadata inventory is a real
state transition and may replace it.

### Local Metadata State

Rewrite the unshipped schema-17 metadata state before merging:

- remove `relayDisclosureAcknowledged`;
- replace root event IDs with `remoteEtag` and `remoteGeneration`;
- retain `enabled`, `dirty`, `dirtyRevision`, attempts, success time, verified
  snapshot revision/content hash, unsupported-version block, and recovery block;
- rename relay/publication terminology to remote backup/store terminology.

Enabling the feature is the explicit storage choice. Do not retain a second
boolean that permits impossible `enabled but disclosure not acknowledged`
states. Disabling stops future stores but preserves dirty work and checkpoints.
It does not delete the remote blob automatically.

Provide an explicit destructive `Delete remote backup` action while disabled
or after a separate confirmation. Successful deletion resets the local remote
checkpoint but does not delete local labels or prevent automatic recovery from
checking an absent object later.

If any Nostr backup build has shipped to production, do not rewrite the schema
or silently strand it. Add a separate, time-bounded migration release that
reads the legacy relay object once, stores it in Bullnym, and removes all relay
code in the following release. The expected case for this PR stack is that no
such build shipped, so no legacy relay migration belongs in the final code.

## Scheduling

### Metadata

Owner transactions still emit post-commit label, frozen-outpoint, and approved
wallet-preference changes. The coordinator coalesces them only to mark durable
dirty state; it does not start a two-second upload timer.

Automatic flush occurs after the app's normal foreground wallet sync reports
success. Only one flush may run at a time. Changes during an in-flight store
advance `dirtyRevision` and remain pending. Startup/resume relies on the normal
sync path where available and has one direct retry fallback when no sync runs.

This bounds the cost for a wallet with roughly 1,000 labels: many edits between
syncs become one fetch plus at most one store. `Back up now` bypasses the wait
but uses the same chokepoint.

### Keychain

Manifest materialization is infrequent and recovery value is highest
immediately after product-wallet creation, so it attempts upload after commit.
Failure never rolls back wallet creation. Durable dirty state supplies retries.

### No Background Cron

There is no periodic background job in V1. Mobile schedulers are not reliable
enough to be correctness infrastructure. Durable dirty state plus sync,
startup, resume, and manual triggers provide eventual catch-up without adding a
new battery or lifecycle subsystem.

## Recovery

After the seed-derived default wallet exists:

1. Acquire the existing recovery/publication-suppression session.
2. Derive the keychain stream signer and encryption key.
3. Fetch and authenticate the keychain blob from Bullnym.
4. If present and valid, plan and materialize missing supported wallets.
5. If absent or unavailable, continue with the normal default wallet. The user
   can run deterministic wallet discovery later.
6. Derive the separate metadata stream signer and encryption key.
7. Fetch, decrypt, validate, and plan the metadata snapshot.
8. Apply labels and freezes additively. Apply wallet preferences only to the
   exact wallet references created during this recovery run; preserve choices
   on pre-existing wallets and defer absent wallets.
9. Release suppression without publishing recovered defaults.
10. Finish seed recovery regardless of Bullnym availability.

The recovery UI may show a progress stage and a final non-blocking summary such
as `Wallet restored; encrypted metadata could not be reached`. It must not ask
for storage consent, enable future backup, or require a retry before entering
the wallet. Unsupported newer backup versions should tell the user to update
the app, but still not block access to funds.

Recovery failure classifications are simplified to:

- no remote backup;
- service unavailable/network failure;
- authentication or device-clock failure;
- malformed or unauthentic ciphertext;
- resource limit exceeded;
- unsupported newer plaintext version;
- local apply incomplete;
- success.

Relay unavailable, partial relay coverage, incomplete graph, older complete
graph, and missing chunk outcomes are deleted.

## UX

### Onboarding

Wallet metadata backup remains the first substantive optional-backup choice in
onboarding. Copy should say that Bull Bitcoin stores an encrypted copy of
labels, frozen-coin state, and selected wallet preferences; Bull Bitcoin can
observe network activity and blob size but cannot read the contents.

The choice is explicit `Enable encrypted metadata backup` or `Not now`.
Recovery lookup is automatic regardless of that choice.

Keychain-manifest backup remains independently activatable where Get Paid or
another deterministic product wallet is enabled. Its copy describes wallet
discovery information, not labels. There is no master toggle that silently
couples both identities.

### Settings

Show each stream independently with:

- enabled toggle;
- `Last backed up` status;
- dirty/pending status when work awaits sync;
- `Back up now`;
- non-secret failure/status copy;
- `Delete remote backup` as an explicit destructive action.

Remove all references to public relays, relay operators, replication,
read-back, chunk counts, and data remaining undeletable on third-party relays.

## Failure Safety

- Never overwrite a current remote blob that cannot be authenticated,
  decrypted, parsed, or understood.
- Never clear dirty work unless the exact captured dirty revision was stored or
  proven canonically identical to the fetched head.
- Never let upload failure fail label edits, freeze changes, preference changes,
  or wallet creation.
- Never let remote recovery failure prevent access to the seed-derived wallet.
- Never let recovered state enable future uploads.
- Never log plaintext, xprvs, encryption keys, fingerprints, public keys,
  ciphertext, labels, wallet references, ETags, or signatures.
- Never retry a conflict by blindly writing the already-built blob; refetch and
  recompose.
- Never reduce malformed/unsupported remote state to `not found`, because that
  could authorize destructive replacement.
- Never infer a wallet for unattributed metadata.

## Deletion Scope in the Wallet PRs

Delete after confirming no other caller remains:

- keychain websocket relay datasource/repository and relay entities;
- keychain Nostr event entities, codecs, event-building and event-publication
  use cases;
- metadata websocket relay and graph repositories;
- metadata relay URL, observation, graph, safe-head, root/chunk-reference,
  encrypted-chunk, and Nostr-event entities;
- metadata Nostr event encoder, frame measurement, partitioner, chunk sizing,
  chunk/root graph codec branches, and graph validation;
- metadata relay/safe-head repository contracts and publication outcomes;
- relay disclosure use cases, state fields, settings copy, and wizard copy;
- backup dependencies on `NostrRelayPolicyFacade`;
- `core/nostr/nostr_relay_transport.dart` and signed-event helpers if no
  non-backup feature uses them;
- relay-specific tests and fixtures.

Keep:

- Nostr/BIP340 identity derivation needed for stream signatures;
- Bullpay signing and all non-backup Bullnym behavior;
- BIP85 registry reservations and golden vectors;
- canonical manifest and metadata codecs after removing transport-only fields;
- contributor export/apply behavior and owner change streams;
- recovery suppression and created-wallet-reference rules.

Remove `nostr_relay_policy` entirely only after a repository-wide reference
check proves that keychain and metadata were its last production callers. Do not
remove the Nostr package merely because backup relay use is gone; other product
features may still need Nostr primitives.

## PR Sequence

### Server PR: Bullnym Opaque Backup Store

- migration and SQLx persistence;
- request/response entities and canonical signed-message builder;
- fetch/store/delete handlers;
- CAS, idempotency, tombstones, body limits, rate limits, and global quota;
- no-secret logging and metrics;
- Rust unit/integration tests and mobile-compatible golden vectors.

Deploy this before any wallet build that calls it. Close or supersede Bullnym
issue #186 because the server is no longer a stateless Nostr broadcast proxy.

### Wallet PR 1: Bullnym Contract and Shared Cipher

- add typed backup operations to `features/bullnym`;
- add cross-repository golden vectors for all three signed actions;
- rename the authenticated cipher away from Nostr;
- add stream-specific signer adapters without changing BIP85 paths;
- no user-facing behavior yet.

### Wallet PR 2: Keychain Manifest Transport Replacement

- replace event build/publish/fetch with Bullnym blob fetch/merge/store;
- add durable keychain backup dirty/checkpoint state;
- rewire Get Paid activation and post-materialization publication;
- simplify automatic keychain recovery outcomes;
- delete keychain relay code and tests.

### Wallet PR 3: Metadata Single-Blob Simplification

- collapse root/chunks into one bounded snapshot;
- replace relay graph/safe-head publication with fetch/merge/CAS store;
- rewrite schema 17 while unshipped;
- preserve all three contributors and future-record preservation;
- delete relay graph, event, chunk, and read-back code.

### Wallet PR 4: Recovery, Scheduling, UX, and Final Cleanup

- run metadata flush after successful foreground sync;
- make both remote recovery checks automatic and non-blocking;
- update onboarding and backup settings copy/actions;
- add explicit remote deletion;
- remove remaining relay policy wiring and generated localization references;
- update `ARCHITECTURE.md`, feature architecture docs, `FEATURES.md`, and DI;
- prove no wallet backup path opens a WebSocket or accepts relay URLs.

Each wallet PR must be independently analyzable and testable. Do not keep both
transports behind a permanent abstraction or runtime toggle. A short-lived
compile-safe transition inside the stack is acceptable; the final PR contains
only Bullnym storage.

## Verification

### Cross-Repository Contract

Check the same golden fixture into Bullnym and mobile for:

- exact fetch/store/delete signed bytes and SHA-256 digest;
- accepted and tampered BIP340 signatures;
- canonical lowercase key/hash/signature formatting;
- ETag calculation;
- canonical base64 and decoded byte count;
- initial store, exact retry, stale ETag conflict, replacement, conditional
  delete, tombstone replacement, and tombstone expiry.

### Mobile Tests

- BIP85 reservation and public-key golden vectors remain unchanged;
- keychain and metadata public keys and encryption keys are distinct;
- wrong-stream encryption key fails authentication;
- one metadata mutation marks dirty without uploading immediately;
- many mutations before sync produce one fetch and at most one store;
- a mutation during store remains dirty;
- keychain entry commit succeeds when upload fails and retries later;
- unchanged content performs no store;
- remote unknown metadata records survive a local update;
- unsupported newer content blocks overwrite;
- corrupt/oversized content blocks overwrite without crashing;
- 409 refetches and recomposes once;
- seed recovery succeeds when Bullnym is absent, slow, 401, 429, or 5xx;
- recovery order is manifest materialization then metadata apply;
- recovery does not enable either stream or trigger publication;
- explicit delete is conditional and does not alter local wallet data;
- a 1,000-label representative fixture round-trips below the 2 MiB decoded
  ciphertext limit;
- analyzer, complete Flutter test suite, package tests, and integration tests
  pass.

### Server Tests

- exact request shape and bounds;
- signature, timestamp, action, stream, hash, size, generation, and ETag
  tampering;
- transaction-safe concurrent writers;
- exact retry after a lost response;
- stale delete cannot remove a newer object;
- old initial store cannot recreate a blob after deletion/auth-window expiry;
- rate limits, distinct-key limits, object-size limit, and global quota;
- fetch/delete remain available when the write quota is full;
- response and logs do not expose plaintext or request bodies.

### Architecture Checks

- product UI imports use cases, not Bullnym HTTP or repositories;
- keychain and metadata import only the Bullnym public facade;
- Bullnym does not import either product feature;
- no datasource calls another datasource;
- no data model crosses a repository/facade boundary;
- no backup production code references relay URLs, EOSE, `EVENT`, Nostr event
  kinds, `d` tags, safe heads, chunks, or WebSockets;
- generated feature dependency documentation remains acyclic.

## Release and Operations

1. Confirm no production mobile release can have created the proposed Nostr
   backups. This decides whether legacy migration is unnecessary as expected.
2. Deploy the Bullnym migration and endpoint with metrics but no client traffic.
3. Run contract tests against staging and the 1,000-label mobile fixture.
4. Deploy the wallet stack with Bullnym only; there is no relay fallback.
5. Monitor request status, latency, conflict rate, size percentiles, total stored
   bytes, quota headroom, and tombstone cleanup. Do not tag metrics by public
   key.
6. Exercise a real seed recovery in staging with Bullnym available, absent, and
   returning a corrupt test blob.
7. Document that Bullnym backups are best-effort convenience data with no
   durability SLA and no effect on self-custody.

## Definition of Done

The rearchitecture is complete when:

- Bullnym can authenticate, store, fetch, replace, and delete one opaque blob
  per stream identity with bounded resources and concurrency safety;
- the wallet publishes and recovers both streams exclusively through Bullnym;
- all frozen BIP85 paths and separate activations remain intact;
- metadata updates are coalesced until successful foreground sync and keychain
  updates remain prompt;
- seed recovery is automatic and never blocked by remote backup failure;
- the three current metadata contributors round-trip correctly and unknown
  future records survive updates;
- the 1,000-label fixture fits in one object;
- all relay event, graph, chunk, disclosure, and WebSocket code used only by
  backups is deleted;
- architecture documents, UX copy, tests, and operations runbooks describe the
  Bullnym-only behavior.
