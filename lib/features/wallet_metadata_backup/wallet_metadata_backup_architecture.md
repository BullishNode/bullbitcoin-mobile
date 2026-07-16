# Wallet Metadata Backup Architecture

## Scope

`wallet_metadata_backup` owns the encrypted wallet-metadata root/chunk/record protocol, contributor coordination, independent backup state, publication triggers, recovery planning, and apply orchestration. V1 implements bounded protocol entities, canonical plaintext codecs, local activation/progress persistence, export, validation, and additive restore for the three approved sections (`labels.bip329`, `wallet.utxo_freeze`, and `wallet.preferences`), one-event inline snapshots with chunked overflow, final-frame-aware encrypted snapshot construction, safe publication coordination, chunks-first/root-last relay publication with exact read-back, complete remote-graph discovery, side-effect-free recovery planning, and transactional owner apply.

The keychain manifest remains a separate backup stream and wire contract. Wallet metadata uses its own Nostr identity, encryption key, activation, publication acknowledgement, publication state, and recovery outcome. Recovery lookup is automatic during seed recovery and is not gated by the publication choice.

## Local State

Schema 17 adds one `wallet_metadata_backup_states` row containing metadata-only activation, relay disclosure acknowledgement, dirty work, publication timestamps, the last verified root, a typed unsupported-newer-envelope block, and a typed recovery-apply block. An absent row is equivalent to the privacy-preserving defaults: disabled, disclosure not acknowledged, and clean.

The off-to-on transition marks the state dirty so pre-existing metadata receives a catch-up attempt once consent and the publication pipeline are available. Repeating an already-on setting is idempotent. Local mutations can mark the state dirty while disabled, but relay contact requires both this feature's `enabled` and `relayDisclosureAcknowledged` values. Neither the keychain-manifest toggle nor its disclosure acknowledgement satisfies this gate.

Disabling stops future metadata relay work while preserving consent, dirty work, timestamps, verified-head knowledge, and any unsupported-newer block. It does not build an empty snapshot or request relay deletion.

The state repository performs read-modify-write transitions inside a Drift transaction so concurrent activation, acknowledgement, and dirty notifications do not clobber one another. Every successful dirty notification increments a persisted `dirtyRevision`, including notifications received while already dirty. A publication captures that revision before building and may clear `dirty` after verification only when the revision is unchanged, preventing a mutation that arrives during publication from being lost. Persisted verified-head and blocked-head columns are reconstructed only when every field is present and valid; partial or unknown states become a typed storage failure.

This table is local control state, not a contributor record. It has no snapshot codec and no public restore setter, so recovered metadata cannot enable itself or grant relay-publication acknowledgement. Recovery orchestration may record a verified remote head or a protective apply block, but activation remains a deliberate local action made in onboarding or Backup Settings.

## Envelope

Envelope version 1 has two encrypted plaintext content types:

- `bullbitcoin.wallet_metadata.root` carries one complete fitting snapshot or indexes its sections and exact chunk event bindings when the snapshot overflows.
- `bullbitcoin.wallet_metadata.chunk` carries complete logical records for one snapshot and chunk index.

`envelopeVersion` is parsed before the remaining root or chunk schema. Any version other than 1 is reported as `unsupportedEnvelopeVersion` and blocks the whole envelope. V1 envelope objects use exact key sets; unknown, missing, duplicate, reordered, or otherwise noncanonical envelope fields are malformed rather than silently discarded.

Each logical record has fixed envelope fields in this order: `type`, `version`, `scope`, `recordId`, and `payload`. Record type and version semantics belong to a future registered contributor. The generic codec retains unknown types, unknown positive versions, scopes, and payloads as deeply immutable structured JSON.

Record identity is `(type, version, canonical scope, recordId)`. Duplicate identities invalidate a chunk even when their payloads differ. Records are ordered by type, numeric version, canonical scope, and record id. Sections are ordered by type, section versions are ordered numerically, and chunk references are ordered by contiguous zero-based index.

## Canonical JSON

Schema object fields use their explicitly frozen order. Keys inside contributor-owned scope and payload objects are sorted lexicographically at every depth; array order is preserved. Canonical output is compact UTF-8 JSON with no whitespace, integer values are signed int64 only, and floating-point JSON values are not part of V1.

The `recordsHash` algorithm is lowercase SHA-256 over the UTF-8 bytes of the compact canonical JSON array containing the canonically ordered complete record objects. A section hash applies the same algorithm to that section's records. A chunk `ciphertextHash` is lowercase SHA-256 over the decoded bytes of its bare authenticated ciphertext. Recovery validates the root's exact event ids, opaque tags, ciphertext hashes, counts, section hashes, aggregate hash, and global record order before a graph can become a restore candidate.

Decoding re-encodes the parsed entity and requires byte-for-byte equality with the input. This rejects alternate field order, whitespace, duplicate JSON keys that `jsonDecode` would otherwise collapse, alternate escaping, and noncanonical record order without maintaining a second handwritten JSON parser.

## Bounds

V1 enforces at most 50,000 logical records, 128 chunks, 12 MiB for any decoded root/chunk document in this codec, 64 KiB for one canonical logical record, 64 KiB for any individual string, 50,000 elements in any JSON collection, nesting depth 32, and signed-int64 numeric values. Complete-graph recovery also enforces the agreed 12 MiB aggregate decrypted-plaintext bound across the root and every chunk, at most 32 configured relays, 20 root events per relay query, and 20 graph candidates per recovery scan.

The 131,000 UTF-8 byte limit applies inclusively to the final serialized Nostr `EVENT` frame and is never approximated from plaintext or ciphertext size. Snapshot construction first places all canonical records in the root, encrypts, signs, serializes, and measures that final frame with `utf8.encode(frame).length`. A fitting snapshot therefore consists of exactly one event. Chunk construction happens only when that measured inline root exceeds the limit.

## Encrypted Nostr Snapshot

Metadata events use kind `30078`, exactly one `d` tag, and bare `base64(nonce16 || AES-256-CBC ciphertext || HMAC-SHA256)` content. The signed-event entity rejects extra tags, malformed opaque tags, noncanonical ciphertext text, wrong kinds, and invalid generic Nostr fields. Public root and chunk frames contain no content type, record type, wallet reference, count, index, app marker, or relation tag.

The encryption key is the first 32 bytes derived from the frozen `1642'/0'/2'` reservation. The expected parent fingerprint is checked against the supplied recovery xprv before any event is encrypted. Signing uses one short-lived wallet-metadata signer derived from `9000'/4'/1'` for the duration of a build; neither raw key is stored in the result or included in failure text.

The stable replaceable root tag is `HMAC-SHA256(metadataEncryptionKey, UTF8("bullbitcoin.wallet_metadata.root.d.v1"))`, encoded as 64 lowercase hex characters. This context and its BIP85-vector output are frozen by a golden test. Each snapshot receives a fresh secure-random 16-byte hex snapshot id, and each chunk receives a distinct fresh secure-random 32-byte hex tag that is also checked against the root tag and every other chunk tag.

Records are sorted canonically before sizing. A root uses exactly one storage mode: non-empty inline `records` with no `chunks`, chunk references with empty `records`, or both empty for an empty snapshot. Mixed storage and non-empty snapshots with neither storage form are malformed. After an inline root overflows, the chunker exponentially increases the number of complete records in a candidate until the signed frame exceeds the limit or reaches the end, then binary-searches the remaining range for the largest fitting candidate. Every probe constructs the canonical chunk document, encrypts it, signs the resulting event id, serializes the complete `EVENT` frame, and measures the actual UTF-8 bytes. A singleton that does not fit returns `WalletMetadataBackupRecordTooLargeFailure`, and needing a 129th chunk returns `WalletMetadataBackupChunkLimitFailure`.

Because `chunkCount` is authenticated inside every chunk, overflow construction starts with the one-, two-, and three-digit ceilings `9`, `99`, and `128`, then repeats partitioning with the actual result until the assumed and produced chunk counts converge. Values with the same decimal width have the same plaintext byte length, while authenticated-ciphertext, event-id, and signature fields have content-independent encoded lengths; tests still measure every emitted frame rather than relying on that fact as a size estimate. The chunk-index root is built only after exact chunk event ids, tags, counts, and ciphertext hashes exist, and a root over the same limit returns `WalletMetadataBackupRootTooLargeFailure`.

The returned snapshot rechecks that every root reference exactly matches its bounded chunk event, that snapshot ids, timestamps, authors, indexes, counts, and hashes agree, and that every emitted frame is within the production ceiling. Inline roots receive the same canonical record, per-record, aggregate count, section, and hash validation as chunked snapshots. Construction also rejects a root-plus-chunks plaintext aggregate over 12 MiB.

## Publication

Publication has one chokepoint guarded by metadata-specific activation and relay consent. It records an attempt, asks the shared graph repository for the current complete authenticated head through the safe-head adapter, and refuses to proceed when any root query lacks EOSE, the newest graph is incomplete, or an authenticated newer envelope requires an app update. This conservative rule prevents a partial relay response from being mistaken for proof that an older root is safe to replace.

Every contributor export must succeed before snapshot construction. Supported local type/version records replace their remote projection, while unknown types, unsupported versions, and empty unknown sections survive composition unchanged. Section declarations participate in the local canonical content hash, so adding support for an empty record version is not collapsed into a records-only no-op.

An initial inventory in which every contributor exported successfully but all sections are empty becomes clean without publishing. Once a verified head exists, a later intentional all-empty inventory is a real snapshot transition. Unchanged complete remote content records that remote head as verified without another write. New snapshots allocate revision `max(local verified, remote complete) + 1` and event time `max(now, highest observed root event time + 1)`; exhausted int64 values fail before encryption.

The relay repository rejects more than 32 distinct targets, then fans out per relay while preserving sequential commit order inside each relay. For an inline snapshot it sends only the root. For an overflow snapshot it requires `OK true` for each exact chunk id before sending that relay the root. It then requires `OK true` for the exact root id before counting an accepted replica. A single bounded `REQ` reads back every emitted event id; generic Nostr verification rechecks every signature and event id, and byte-for-byte signed-frame equality verifies the complete replica. Accepted-but-unverified is retryable and leaves `dirty` set. At least one verified replica records the canonical content head and may clear only the captured dirty revision, so a local mutation arriving during publication remains pending.

## Change Tracking and Scheduling

Labels, frozen-outpoint storage, and represented wallet preferences expose owner-controlled post-commit change streams. A successful owner transaction emits only after commit; failed writes do not create false publication work. Structural wallet writes that do not change `label`, `hideOnHome`, or `autoSweepEnabled` do not dirty this backup.

The metadata coordinator is the single automatic-publication driver. Every committed label, frozen-outpoint, or represented wallet-preference change emits through its owner change stream. The coordinator coalesces bursts into one dirty-state update, debounces publication for two seconds, permits only one publication in flight, and retries pending work at cold start and when the app resumes. A mutation observed during an in-flight attempt remains dirty and schedules a follow-up attempt. Changes observed during recovery suppression remain dirty, and releasing the coordinator-owned suppression schedules the same retry path. Enabling the backup, accepting its publication disclosure, or explicitly marking it dirty also schedules that chokepoint; the settings screen's `Back up now` action calls it directly. There is no periodic cron: mobile background scheduling is not the source of truth, and durable dirty state plus owner events and lifecycle retries provide deterministic catch-up without unnecessary relay queries or battery use.

Publication suppression and owner-change suppression are separate. A keychain or metadata recovery session acquires suppression before doing owner work and waits for any already-running publication to finish, so recovery cannot overlap relay publication. A failed in-flight publication does not prevent the recovery session from acquiring suppression. Owner writes during the session may still mark metadata dirty without contacting relays. After keychain materialization, the flow retains the same token while it automatically checks and applies metadata; this prevents app resume from publishing newly created local defaults before remote metadata has been considered. Metadata apply suppresses its own owner notifications because the apply use case writes the definitive dirty/verified/block state transactionally. Suppression tokens are idempotent and are released on success, failure, terminal no-snapshot outcomes, navigation disposal, and cubit disposal.

## Recovery Planning

Recovery is automatic after the seed-derived default wallet is available and is not gated by publication activation or acknowledgement. The flow derives the separate metadata identity and encryption key, then queries every policy relay for the exact author, kind, and stable root `d` tag. This lookup does not enable future backups, acknowledge publication, or publish an event. Only a successful EOSE proves one relay's root inventory complete; event limits, timeouts, `CLOSED`, stream closure, and connection failures remain partial or unavailable observations.

Every relay event is independently signature- and id-verified. Root ciphertext is authenticated and decrypted before parsing, but `envelopeVersion` is classified before the remaining schema so a newer app's root becomes a durable update-required observation rather than "no backup" or malformed data. Compatible roots are ordered by authenticated revision, event timestamp, and event id. Recovery attempts a bounded newest-first set and may assemble exact referenced chunks across different relays.

An inline graph is complete after its root records pass global canonical order, unique identity, section count and hash, aggregate count and hash, and resource-limit validation; recovery makes no chunk request. An overflow graph is complete only when every referenced chunk has the exact signed event id, author, kind, opaque tag, timestamp, ciphertext hash, snapshot id, index, count, and authenticated plaintext expected by its root. Chunk recovery prioritizes relays that supplied the candidate root, processes one bounded relay response at a time, and stops once all exact references are present; this avoids retaining duplicate 128-chunk responses from every relay at once while still allowing assembly across relays. The reconstructed records receive the same integrity validation. An intentional empty root is also complete without chunk requests.

Recovery may offer the newest complete older graph when a newer root is unreadable, incomplete, resource-limited, or from an unsupported envelope, or when relay coverage is partial. The plan reports that it is older and retains the newer blockers; publication remains blocked. Complete absence, unavailable relays, authentic-but-incomplete roots, and unsupported newer envelopes are distinct outcomes.

Planning is side-effect-free except for persisting an authenticated unsupported-envelope block. Registered contributors validate only the type and versions they own and emit import intents; invalid owned records are reported without exposing private record ids. Unknown types, unsupported versions, and unsupported section declarations remain visible in the plan and are not silently interpreted or discarded. A valid plan is applied automatically under publication suppression. No planning or apply outcome publishes an event.

## Recovery Apply

Apply first proves that every planned intent is an exact canonical record from the selected authenticated head and still passes its owner's validator. A forged, duplicated, missing, or mutated intent fails before local state or contributor stores are touched. The use case then persists an `applyInProgress` recovery block before any owner write, preventing an interruption from leaving automatic publication able to overwrite the selected relay head.

Before apply writes any state, it re-derives the current local recovery root and requires its normalized parent fingerprint to match the authenticated snapshot. This prevents a preview fetched for one owner from being applied after the local owner changes. Each owner then applies its intents through its own transactional boundary. Labels restore additively by the portable BIP329 identity and preserve existing local rows; frozen outpoints restore only `frozen:true` rows and never unfreeze local coins; wallet preferences overwrite product defaults only for wallet references materialized in this same keychain-recovery run. Preferences for pre-existing wallets preserve local choices, and references for absent wallets are deferred. One owner's storage failure does not roll back another owner's committed metadata, but the aggregate result remains incomplete and publication-blocked.

An exact latest apply records the selected canonical head as verified and clean. An older selected graph, partial relay coverage, unsupported records or section declarations, invalid owned records, a deferred/conflicting projection, a missing contributor, or a storage failure leaves dirty work plus a typed `olderSnapshot` or `incompleteApply` block. Recovery never republishes automatically, including after a latest complete apply; the verified head only makes later user changes safe to publish through the normal chokepoint.

Remote recovery starts only after keychain-manifest recovery has decided which wallets exist. It passes the exact set of wallets created in that run into metadata apply. Metadata has no authority to create wallets, infer a wallet owner, reactivate a product, or alter keychain-manifest material.

## BIP329 Labels

`labels.bip329` version 1 contains one complete BIP329 object per global record. The representable payload fields are the frozen wire `type`, `ref`, `label`, and optional `origin` values owned by the current labels table. All six current types (`tx`, `addr`, `pubkey`, `input`, `output`, and `xpub`) preserve their origins. Device-local integer ids are never exposed.

The labels facade has a strict backup export separate from its best-effort enrichment reads. A storage or codec failure remains a typed failure, so publication orchestration cannot mistake failure for an intentionally empty section. The facade publishes a validated annotation entity without JSON behavior; the labels-owned codec maps that entity to and from BIP329 wire models, while this feature maps it to the generic metadata payload.

The portable record id is lowercase SHA-256 over UTF-8 `labels.bip329/v1\n` followed by the compact JSON object `{"label":<label>,"ref":<ref>}`. This matches the labels store's portable `(label, reference)` upsert key and deliberately excludes the local id. Type and origin remain payload fields and can change without changing that natural identity. If a local row with that identity has different type or origin, recovery reports a conflict and preserves the local row rather than updating it.

This backup path carries annotations only. It rejects `spendable` and never emits freeze-only output records. User-facing BIP329 file interchange retains its existing `spendable:false` projection; encrypted metadata backup will export exact freeze state through the separate `wallet.utxo_freeze` contributor.

## Frozen UTXOs

`wallet.utxo_freeze` version 1 reads the freeze store through `WalletUtxoRepository`, which publishes a validated `FrozenWalletOutpoint` domain entity rather than exposing Drift rows. Every payload contains the exact stored `walletRef`, lowercase 64-hex `txid`, unsigned 32-bit `vout`, and `frozen:true`. Wallet ids are never reduced to BIP329 origins, so Liquid-testnet, multisig, imported, and unusual ids survive byte-for-byte.

An attributed row has scope `{"kind":"wallet","walletRef":<exact id>}`. The empty wallet id used by an imported freeze with no trustworthy attribution has scope `{"kind":"unattributed"}` and keeps `walletRef:""` in its payload. Recovery must preserve that state and must never guess a wallet from an outpoint. The row remains inert when no live wallet owns the coin; freeze enforcement and unfreeze behavior continue to match globally by outpoint.

The stable record id is the canonical outpoint string `txid:vout`. Scope is part of generic record identity, so the current table's exact rows remain representable even if legacy data attributes the same globally unique outpoint to more than one wallet id. Reapplying one freeze is idempotent through the existing `(walletId, txId, vout)` upsert, while unfreeze continues to clear every attribution for the globally unique outpoint.

## Wallet Preferences

`wallet.preferences` version 1 reads through a narrow `WalletPreferencesRepository` and `GetWalletPreferencesUsecase`. Their domain entity exposes only the exact wallet reference and the nullable `label`, `hideOnHome`, and `autoSweepEnabled` values. It cannot expose xpubs, descriptors, fingerprints, signer information, default-wallet structure, birthdays, sync state, balances, backup-tested state, or backup timestamps.

Null means a preference is not represented in storage; export never replaces it with a UI or product default. Null fields are omitted from payload, explicit `false` and an explicit empty label remain represented, and a wallet with no represented V1 preference emits no record. The payload repeats the exact `walletRef`, scope is `{"kind":"wallet","walletRef":<exact id>}`, and the one record in that scope uses stable id `preferences`.

Restore policy is ownership-aware. A wallet created in the current unified recovery may receive backup values over its product defaults. A pre-existing wallet keeps its local choices and reports a conflict. A wallet that is still absent is deferred, even if recovery expected to create it. Recovered metadata never supplies wallet material or causes a missing wallet to be guessed or created.

## Boundaries

- `core/nostr` owns generic signed-event, authenticated-ciphertext, and one-relay transport mechanics.
- `bip85_registry` owns the metadata signing and encryption reservations.
- `nostr_identity` owns role-named metadata public-key derivation and signing, including the short-lived signing handle used during candidate sizing.
- Record contributors own export, payload validation, import intent, and apply semantics for their types. The labels implementation consumes only the labels public facade; freeze and preferences consume narrow wallet domain repository/use-case contracts. None reaches into another owner's Drift table.
- This feature retains and coordinates contributor records but never reaches directly into another feature's internal store.
- `wallet_metadata_backup/public` is the only cross-feature contract. Recovery exposes an opaque plan handle plus aggregate counts; decrypted records, graph observations, and contributor intents remain internal. Backup Settings and Remote Keychain Recovery wrap that facade in their own use cases; their cubits do not call it directly.
- The feature watcher calls dirty/publication use cases and never reaches around them into Drift or contributor stores.
