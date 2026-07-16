# GETPAID-2 Bullnym Backup Implementation Plan

## Objective

Create a second, independent Get Paid stack that preserves the existing Nostr
stack unchanged while replacing wallet backup relay usage with Bullnym opaque
blob storage.

The result is:

```text
origin/develop
  |-- existing Get Paid 01-45          (untouched Nostr stack)
  `-- GETPAID-2 01-49                  (Bullnym backup stack)
```

GETPAID-2 PRs 01-15 retain the existing product foundation. GETPAID-2 PRs
16-24 replace the Nostr keychain-backup work. PRs 25-45 replay the later Get
Paid work. PRs 46-49 add wallet-metadata backup using the same Bullnym service.

The original branches, commits, PRs, reviews, and CI evidence are never force
pushed or deleted.

The protocol and product decisions are specified in
`docs/wallet-backup-bullnym-rearchitecture.md`. This plan specifies how to
implement and restack them.

## Testing and Restacking Decision

### What is deferred

Do not continuously rebase, regenerate, build, and run the full suite on every
GETPAID-2 branch while implementation is changing.

Instead:

1. Implement on a small number of work branches.
2. Use focused tests while editing.
3. Integrate and run the complete mobile suite at the final GETPAID-2 tip.
4. Fetch the latest source stack once.
5. Construct and push the complete alternative branch chain once.
6. Perform cheap structural validation on every branch without building it.

This avoids paying for a 30-branch restack every time a shared contract changes.

### Important limitation

A passing tip does not mathematically prove that every ancestor compiles. A
later PR can add an import, generated file, registration, or bug fix required by
an earlier PR. Therefore tip-only testing is appropriate as an implementation
optimization, not as final merge evidence for independently reviewable PRs.

The execution policy is:

- during implementation, run one full mobile validation at the final tip;
- run focused tests in the work areas as feedback, not the full suite per PR;
- validate every constructed branch structurally;
- allow required GitHub checks to run in parallel after PR creation or when
  each PR reaches review/merge, without making them part of the three-hour
  construction critical path;
- if strict confidence is required before opening the stack, also run the full
  suite at PR24, the replacement-backup boundary. This is optional for initial
  construction but recommended before merging PR16.

No CI workflow is weakened and no test is marked skipped to make the stack
green.

## Branch and PR Naming

Use lowercase Git branch names and uppercase PR title identifiers.

Example:

```text
branch: getpaid-2-16-keychain-backup-ciphertext
title:  [GETPAID-2 16] Keychain backup ciphertext contract
```

Do not use a `/45` denominator. Wallet metadata extends the stack beyond 45.

### Branch map

PRs 01-15 preserve the current logical changes under a separate branch name:

| ID | GETPAID-2 branch |
| --- | --- |
| 01 | `getpaid-2-01-bip85-deterministic-wallet-foundation` |
| 02 | `getpaid-2-02-btcpay-samrock-pairing` |
| 03 | `getpaid-2-03-btcpay-registry-wallet-defaults` |
| 04 | `getpaid-2-04-keychain-manifest-reserved-wallets` |
| 05 | `getpaid-2-05-keychain-manifest-file-contract` |
| 06 | `getpaid-2-06-keychain-manifest-file-import` |
| 07 | `getpaid-2-07-keychain-recovery-wallet-restore` |
| 08 | `getpaid-2-08-get-paid-reserved-path-registry` |
| 09 | `getpaid-2-09-nostr-compatible-identity-roles` |
| 10 | `getpaid-2-10-bullnym-protocol-foundation` |
| 11 | `getpaid-2-11-lightning-address-foundation` |
| 12 | `getpaid-2-12-lightning-address-wallet-materialization` |
| 13 | `getpaid-2-13-lightning-address-wallet-registration` |
| 14 | `getpaid-2-14-lightning-address-activation-ui` |
| 15 | `getpaid-2-15-lightning-address-autosweep-readiness` |

PR09 deliberately says `nostr-compatible`: deterministic x-only/BIP340 key
derivation remains, but GETPAID-2 backup code does not publish Nostr events or
connect to relays.

PRs 16-24 are replacement changes, not replays:

| ID | GETPAID-2 branch | Purpose |
| --- | --- | --- |
| 16 | `getpaid-2-16-keychain-backup-ciphertext` | Provider-neutral authenticated ciphertext and frozen key paths |
| 17 | `getpaid-2-17-bullnym-backup-blob-contract` | Typed Bullnym fetch/store/delete mobile contract and signing fixtures |
| 18 | `getpaid-2-18-keychain-bullnym-repository` | Keychain snapshot fetch, merge, conditional store, and delete |
| 19 | `getpaid-2-19-keychain-backup-state` | Durable activation, dirty revision, checkpoint, and retry state |
| 20 | `getpaid-2-20-encrypted-backup-privacy-controls` | Bullnym storage disclosure and independent keychain activation |
| 21 | `getpaid-2-21-keychain-bullnym-import-plan` | Authenticated Bullnym fetch/decrypt/parse/import planning |
| 22 | `getpaid-2-22-remote-keychain-recovery` | Automatic non-blocking keychain recovery orchestration |
| 23 | `getpaid-2-23-remote-recovery-ux` | Recovery progress, summary, retry entry point, and failure mapping |
| 24 | `getpaid-2-24-automated-keychain-backup` | Post-materialization upload, retries, Get Paid settings, integration fixtures |

PRs 25-45 retain the existing titles and logical deltas, replayed onto
GETPAID-2 PR24:

| ID | GETPAID-2 branch |
| --- | --- |
| 25 | `getpaid-2-25-lud22-liquid-direct-pay` |
| 26 | `getpaid-2-26-payment-page` |
| 27 | `getpaid-2-27-point-of-sale` |
| 28 | `getpaid-2-28-invoices` |
| 29 | `getpaid-2-29-get-paid-dashboard` |
| 30 | `getpaid-2-30-wallet-controls` |
| 31 | `getpaid-2-31-sweep-labels` |
| 32 | `getpaid-2-32-payment-page-social-preview` |
| 33 | `getpaid-2-33-typed-bullnym-results` |
| 34 | `getpaid-2-34-permanent-name-protocol` |
| 35 | `getpaid-2-35-permanent-nym-availability` |
| 36 | `getpaid-2-36-shared-alias-availability` |
| 37 | `getpaid-2-37-automatic-fallback-contract` |
| 38 | `getpaid-2-38-automatic-fallback-setup` |
| 39 | `getpaid-2-39-automatic-fallback-supervision` |
| 40 | `getpaid-2-40-honest-payment-history` |
| 41 | `getpaid-2-41-exact-payer-amounts` |
| 42 | `getpaid-2-42-long-lived-invoice-quotes` |
| 43 | `getpaid-2-43-private-lnurl-comments` |
| 44 | `getpaid-2-44-registration-identity-contract` |
| 45 | `getpaid-2-45-registration-contract-fixture` |

Wallet metadata follows the replayed stack:

| ID | GETPAID-2 branch | Purpose |
| --- | --- | --- |
| 46 | `getpaid-2-46-wallet-metadata-model` | Canonical records, local state, and three contributors |
| 47 | `getpaid-2-47-wallet-metadata-bullnym-storage` | Single encrypted snapshot, fetch/merge/CAS store, deletion |
| 48 | `getpaid-2-48-wallet-metadata-scheduling-settings` | Dirty tracking, sync-triggered flush, onboarding, settings |
| 49 | `getpaid-2-49-automatic-metadata-recovery` | Automatic apply, final relay cleanup, architecture and integration tests |

The final denominator can be added only after scope stops moving.

## Worktree and Ownership Model

Use four agents in isolated worktrees. No two agents edit the same checkout.

### Agent A: Bullnym server

Repository: `bullnym`.

Owns:

- Rust API contract and canonical signing bytes;
- PostgreSQL migration and data access;
- fetch/store/delete handlers;
- CAS, idempotency, tombstones, limits, rate limiting, and metrics;
- Rust tests and shared protocol fixture.

Does not edit the mobile repository.

### Agent B: keychain mobile replacement

Base: current Get Paid PR15 tip.

Owns:

- GETPAID-2 replacement commits 16-24;
- shared provider-neutral cipher rename;
- Bullnym mobile blob contract;
- keychain backup state, publication, recovery, and Get Paid controls;
- removal of keychain relay/event dependencies.

Agent B writes nine ordered, reviewable commit groups matching PR16-24. It does
not create or rebase the final branch chain.

### Agent C: wallet metadata

Base: immutable checkpoint of the current PR45 metadata work.

Owns:

- preserving the current Nostr metadata implementation on an archive branch;
- reducing root/chunks/relay graphs to one Bullnym blob;
- metadata contributors and state;
- sync scheduling, onboarding/settings, and automatic recovery;
- four ordered commit groups matching PR46-49.

Agent C may use a temporary adapter against the current Bullnym facade contract.
The final cherry-pick onto GETPAID-2 PR45 resolves the actual shared API once.

### Agent D: stack and integration

Base: no implementation ownership during the first phase.

Owns:

- source-stack manifest and immutable checkpoints;
- cross-repository golden fixture coordination;
- fake Bullnym client and integration harness coordination where files are not
  owned by Agent B or C;
- replay of PR25-45 after Agent B completes PR24;
- cherry-pick/integration of PR46-49;
- generated files, formatting, final suite, branch creation, pushes, and PRs.

Agent D is the only agent allowed to rewrite GETPAID-2 branch refs.

## Phase 0: Preserve and Inventory

1. Fetch `origin` in both repositories.
2. Record the exact source mapping for Get Paid 01-45 in a machine-readable
   manifest containing ID, title, base branch, head branch, base SHA, head SHA,
   and commit range.
3. Confirm every source head descends from its declared source base.
4. Confirm the current PR45 head and `origin/develop` SHA.
5. Create immutable local and remote archive refs for:
   - the current original PR45 tip;
   - the current uncommitted metadata implementation after committing it as a
     clearly marked checkpoint;
   - any local changes not represented by a remote branch.
6. Export `git status`, `git diff --stat`, and the list of untracked files into
   the archive commit description.
7. Do not reset, force push, or modify any existing `pr00` through `pr44`
   branch.
8. Create four worktrees with explicit branch names and ownership.
9. Freeze the V1 mobile/server contract fixture before independent coding
   begins.

Gate: all current Nostr work is recoverable from remote refs and the source
stack manifest can reconstruct the existing chain without relying on working
tree state.

## Phase 1: Freeze the Cross-Repository Contract

1. Copy the HTTP request, response, signed-byte, ETag, limit, and failure
   definitions from the architecture document into one JSON fixture.
2. Include deterministic vectors for:
   - keychain fetch;
   - metadata fetch;
   - initial store;
   - replacement store;
   - exact retry;
   - conditional delete;
   - stale ETag conflict;
   - invalid action, stream, hash, size, timestamp, and signature.
3. Use fixed private keys only in test fixtures.
4. Record expected x-only public key, signed bytes as hex, SHA-256 digest,
   signature, ciphertext hash, and ETag.
5. Check identical fixture bytes into Bullnym and mobile.
6. Agent A verifies vectors with Rust/secp256k1.
7. Agent B verifies vectors with the mobile signer implementation.
8. Neither implementation changes the fixture independently. Contract changes
   require one coordinated fixture revision.

Gate: both languages accept every valid vector and reject every tampered vector.

## Phase 2: Bullnym Server Implementation

### 2.1 Persistence

1. Add the next migration for `wallet_backup_blobs`.
2. Store stream enum, 32-byte author key, generation, 32-byte ETag, decoded
   ciphertext bytes/hash/size, timestamps, and nullable deletion timestamp.
3. Enforce closed stream values, exact byte lengths, generation bounds, blob
   size, and live-versus-tombstone column consistency in SQL.
4. Add narrow DB functions for fetch-for-author, transactional conditional
   replace, conditional delete, and expired-tombstone cleanup.
5. Use row locking or an atomic UPSERT condition so concurrent stores cannot
   both advance the same head.

### 2.2 Authentication

1. Add `bullbitcoin-wallet-backup-v1` signing-message construction.
2. Reuse the existing SHA-256 plus BIP340 verifier, but not
   `bullpay-la-v2` action construction.
3. Validate canonical lowercase public keys, hashes, ETags, and signatures.
4. Validate the 300-second timestamp window.
5. Bind action, stream, identity, generation, expected ETag, hash, byte count,
   and timestamp into every signature.
6. Verify body size and source rate limits before signature verification.

### 2.3 Endpoints

1. Implement authenticated fetch with found/absent/tombstone responses.
2. Implement initial store requiring generation one and no expected ETag.
3. Implement replacement requiring current ETag and generation plus one.
4. Return success for an exact retry after a lost response.
5. Return typed 409 for stale writes without leaking the current blob.
6. Implement conditional delete and ten-minute tombstone retention.
7. Keep fetch and delete available when the global write quota is exhausted.
8. Add a bounded cleanup task for expired tombstones.

### 2.4 Operations

1. Add route-specific body limits.
2. Add source, authenticated-key, distinct-key, and global-byte controls.
3. Ensure trusted-proxy source extraction follows existing Bullnym policy.
4. Prohibit body, ciphertext, public-key, ETag, and signature logging.
5. Add aggregate action/stream/status/latency/size-bucket metrics.
6. Document configuration and rollback behavior.

### 2.5 Server verification

Run focused tests while coding, then at the server PR tip run formatting,
Clippy, all Rust tests, SQL migration tests, concurrent-writer tests, contract
fixtures, and a local PostgreSQL HTTP round trip.

Gate: the server PR is green and deployable before a production mobile build is
released. Mobile coding may proceed against the frozen fake contract.

## Phase 3: Mobile Keychain Replacement, PR16-24

### PR16: ciphertext contract

1. Rename the generic authenticated cipher away from Nostr terminology.
2. Keep RecoverBull-compatible authenticated ciphertext bytes unchanged.
3. Preserve keychain signing `9000'/1'/1'` and encryption `1642'/0'/1'`.
4. Replace Nostr-event wrappers with a provider-neutral encrypted keychain
   snapshot entity and codec.
5. Keep manifest file format/import logic unchanged.
6. Add wrong-key, mutation, canonical-base64, and size-bound tests.

### PR17: Bullnym blob client

1. Extend `features/bullnym` through its existing
   `facade -> usecase -> repository/client -> Dio` architecture.
2. Add domain entities for stream, remote head, fetch result, store request,
   store receipt, and delete receipt.
3. Add exact signed-message construction and golden tests.
4. Add typed facade methods for fetch/store/delete.
5. Map status codes and server error codes into `BullnymFailure` values.
6. Keep request JSON and Dio types inside the Bullnym data layer.
7. Ensure product features supply only a short-lived signer capability.

### PR18: keychain Bullnym repository

1. Add a keychain-owned repository that builds/decrypts keychain snapshots and
   calls the Bullnym public facade.
2. Fetch current remote state before every non-idempotent store.
3. Authenticate, decrypt, and parse a present remote snapshot.
4. Merge compatible manifest entries with existing conflict rules.
5. Refuse to overwrite corrupt, unauthentic, oversized, or newer-version data.
6. Conditionally store one ciphertext blob.
7. Refetch and recompose once after a 409.
8. Add explicit conditional remote deletion.

### PR19: durable keychain state

1. Add one local keychain-backup state row.
2. Persist enabled, dirty, dirty revision, attempts, success, remote generation,
   remote ETag, content hash, and unsupported-version block.
3. Mark dirty in the same local transaction that records a manifest entry.
4. Clear only the captured dirty revision after verified success/identity.
5. Preserve dirty work while disabled.
6. Regenerate Drift schema and migration fixtures once in this commit.

### PR20: activation and privacy controls

1. Replace relay consent with explicit encrypted Bullnym storage activation.
2. Keep keychain activation independent of metadata activation.
3. Update disclosure: Bullnym sees IP, timing, stream pseudonym, and size but not
   plaintext.
4. Disabling stops writes and does not silently delete remote data.
5. Add an explicit confirmed delete action.

### PR21: import planning

1. Derive the stream signer and encryption key from the recovery seed.
2. Fetch by signed Bullnym request without requiring publication activation.
3. Verify, decrypt, parse, and produce the existing import plan.
4. Simplify remote outcomes to absent, unavailable, invalid, too large, newer
   version, conflict, and success.
5. Remove relay inventory, event selection, and partial-coverage behavior.

### PR22: recovery orchestration

1. Run keychain lookup automatically after the seed-derived default wallet is
   available.
2. Materialize supported wallets from a valid plan.
3. Continue normal recovery on absent or unavailable Bullnym.
4. Do not enable uploads or publish after recovery.
5. Preserve deterministic wallet discovery as the manual fallback.

### PR23: recovery UX

1. Replace relay-specific progress/failures with Bullnym-neutral backup status.
2. Make every remote failure non-blocking for access to funds.
3. Surface unsupported newer data as an update-app recommendation.
4. Provide a later retry entry point without requiring recovery-screen retry.
5. Update localization and widget tests.

### PR24: automated backup integration

1. Upload promptly after manifest materialization commits.
2. Never fail wallet creation because remote upload failed.
3. Retry durable dirty work at startup, resume, and successful wallet sync.
4. Rewire Get Paid settings to keychain backup use cases.
5. Replace fake relay integration support with a fake Bullnym blob client.
6. Remove production and test dependencies on relay policy for keychain backup.
7. Delete remaining keychain relay/event code that has no non-backup caller.
8. Update architecture and feature dependency documents.

Gate: PR24's tree has no keychain backup WebSocket, relay URL, Nostr event,
kind, `d` tag, EOSE, or relay disclosure path.

## Phase 4: Replay Existing PR25-45 Once

Agent D performs this phase only after Agent B's PR24 commit series is stable.

For each source PR from 25 through 45:

1. Read its exact old base and head SHAs from the frozen stack manifest.
2. Enumerate commits in `old_base..old_head` in topological order.
3. Cherry-pick those commits onto the previous GETPAID-2 branch tip, preserving
   author and commit message.
4. Resolve conflicts according to the final Bullnym architecture, never by
   restoring relay APIs merely to satisfy an old call site.
5. Regenerate files only when the source PR logically changes their inputs.
6. Record conflict resolutions in a restack log by PR and file.
7. Create the next local GETPAID-2 branch pointer.
8. Do not push yet.

Expected conflict concentrations:

- PR26-30: recovery UI, locator, labels, wallet preferences, localization;
- PR33: broad typed Bullnym result refactor;
- PR38: recovery orchestration and Bullnym contracts;
- PR44: Nostr-compatible signer identity API.

For PR33, preserve its typed-result architectural improvement and port the
backup blob methods into the resulting typed Bullnym API. Do not retain a
temporary pre-PR33 Bullnym API at the final tip.

Gate: local GETPAID-2 PR45 contains every intended source delta from PR25-45,
with only documented transport-related adaptations.

## Phase 5: Wallet Metadata, PR46-49

### PR46: metadata model and contributors

1. Preserve canonical generic records and section declarations.
2. Preserve unknown record types and positive versions.
3. Preserve BIP329 labels, frozen UTXOs, and approved wallet preferences.
4. Preserve additive labels, freeze-only apply, and created-wallet preference
   rules.
5. Add provider-neutral local state using enabled, dirty revision, checkpoint,
   unsupported-version block, and recovery block.
6. Set decoded-ciphertext limit to 2 MiB and add a representative 1,000-label
   fixture.

### PR47: Bullnym metadata storage

1. Keep metadata signing `9000'/4'/1'` and encryption `1642'/0'/2'`.
2. Encode all metadata records in one canonical encrypted snapshot.
3. Fetch, authenticate, decrypt, and validate the current remote blob.
4. Preserve unknown remote records during local composition.
5. Skip store when canonical content is unchanged.
6. Conditionally store one blob; refetch/recompose once on 409.
7. Add explicit conditional deletion.
8. Remove root/chunk, frame sizing, event ID, safe-head, graph, EOSE, replica,
   and relay read-back machinery.

### PR48: scheduling and settings

1. Keep owner post-commit change streams.
2. Coalesce changes into durable dirty state without a two-second upload timer.
3. Flush after successful foreground wallet sync.
4. Permit only one in-flight flush and preserve concurrent dirty revisions.
5. Retry at startup/resume only when normal sync does not provide a trigger.
6. Add `Back up now`, pending, last success, failure, toggle, and delete controls.
7. Put the explicit metadata-backup choice prominently in onboarding.
8. Do not couple keychain and metadata activation.

### PR49: automatic recovery and cleanup

1. Retain publication suppression through keychain then metadata recovery.
2. Fetch metadata automatically after keychain recovery decides which wallets
   exist.
3. Apply metadata without enabling backup or triggering publication.
4. Treat unavailable/invalid metadata as a non-blocking recovery result.
5. Preserve incomplete-apply protection and deferred wallet references.
6. Delete all now-unused backup relay policy, WebSocket transport, Nostr event,
   root/chunk, disclosure, fixture, and generated localization references.
7. Update all architecture docs and `FEATURES.md`.
8. Add end-to-end seed recovery with Bullnym available, absent, and corrupt.

Gate: a repository-wide production-code search proves that wallet backup paths
do not accept relay URLs or open WebSockets. Nostr-compatible identity
derivation remains only for signing/authentication roles and unrelated product
features.

## Phase 6: Final Integration Validation at the Tip

Run this against GETPAID-2 PR49 before creating remote branches or PRs:

1. Verify the working tree contains only intended generated changes.
2. Run Dart formatting checks.
3. Regenerate Drift, localization, mocks, and feature documentation through
   repository-supported commands.
4. Run analyzer with no ignored new diagnostics.
5. Run the complete Flutter unit/widget suite.
6. Run package tests.
7. Run Get Paid and backup integration tests.
8. Run a debug application build through the same command as CI.
9. Run the 1,000-label size/performance fixture and record plaintext,
   ciphertext, HTTP body size, encode/decode time, and apply time.
10. Run cross-repository mobile/server golden fixtures.
11. Run a real local Bullnym HTTP round trip for both streams.
12. Test seed recovery with:
    - both blobs present;
    - neither blob present;
    - Bullnym unavailable;
    - wrong signature/401;
    - rate limit/429;
    - stale store/409;
    - corrupt ciphertext;
    - unsupported newer plaintext;
    - metadata referring to absent wallets.
13. Run `git diff --check` and scan for secrets/private metadata in logs.
14. Review final architecture dependencies and deletion list.

Gate: mobile PR49 and the Bullnym server PR are both green. A failure is fixed
in its owning logical commit, then replayed forward locally; it is not patched
only at the tip if the defect belongs to an earlier PR.

## Phase 7: One Final Source Refresh and Restack

This is the only planned rebase against moving source branches.

1. Fetch `origin` and refresh GitHub PR metadata.
2. Compare every source PR head SHA with the Phase 0 manifest.
3. If none changed, continue without rebasing.
4. If PR01-15 changed, rebuild the corresponding GETPAID-2 aliases and replay
   replacement PR16-24 once.
5. If PR25-45 changed, replay only changed source commit ranges plus their
   descendants.
6. Never rebase onto the old PR45 tip as one squashed diff; use declared PR
   commit ranges so review boundaries remain meaningful.
7. Reapply PR46-49 onto the refreshed GETPAID-2 PR45.
8. Resolve generated files by regeneration, not conflict-marker editing.
9. Rerun the final-tip checks affected by conflict resolution. If conflicts
   touch shared contracts, recovery, storage, DI, or generated schema, rerun the
   complete tip suite.
10. Freeze the final source manifest and GETPAID-2 branch SHAs.

This phase absorbs upstream movement once, after implementation has stopped
changing. If the source stack changes again after this gate, evaluate the delta
rather than automatically starting another full restack.

## Phase 8: Per-Branch Structural Validation

Without building each branch, validate GETPAID-2 PR01-49 mechanically:

1. Every branch has exactly the prior GETPAID-2 branch as an ancestor.
2. Every PR delta is non-empty and contains only its intended logical scope.
3. Every cherry-picked source commit appears in exactly one GETPAID-2 PR range.
4. No conflict markers, patch whitespace errors, or untracked generated files
   exist.
5. Changed Dart files are formatted.
6. Deleted APIs have no references at that branch tip based on source search.
7. Each branch's migration/schema-version relationship is internally ordered.
8. Generated files change in the same PR as their source inputs.
9. PR descriptions list base, replacement/replay source, testing performed,
   and known dependency on later validation.
10. Compare tree manifests at PR45 to ensure all non-backup source-stack files
    were preserved unless a conflict resolution was documented.

This catches stack-construction mistakes cheaply. It does not replace eventual
per-PR CI before merge.

## Phase 9: Push and Open the Alternative Stack

1. Push archive refs first and verify they exist remotely.
2. Push GETPAID-2 branches in ascending order with `--force-with-lease` only if
   updating an already-created GETPAID-2 branch.
3. Never use a force push against the original stack branches.
4. Open PR01 against `develop` and every later PR against the previous
   GETPAID-2 branch.
5. Open PRs as drafts until the full tip and server gates are green.
6. Use titles `[GETPAID-2 NN] <title>`.
7. In every PR body include:
   - alternative-stack purpose;
   - exact base PR;
   - corresponding original PR when replayed;
   - statement that original Nostr work is preserved;
   - whether changes are identical, adapted, or replacement work;
   - test scope;
   - link to the architecture and this plan.
8. Mark PR16 as the point where GETPAID-2 intentionally diverges from the
   original Nostr backup stack.
9. Mark PR49 as the only initial full-stack validation tip.
10. Link the Bullnym server PR from PR17, PR24, PR47, and PR49.

Required GitHub checks may fan out after PR creation. They are not run
sequentially as a prerequisite to opening the next branch. Any intermediate
failure is fixed in that PR's logical commit and replayed through descendants.

## Phase 10: Deployment and Release

1. Merge and deploy the Bullnym server before releasing any GETPAID-2 mobile
   build that enables remote backup.
2. Verify production capability, body limits, DB migration, rate limits,
   metrics, and tombstone cleanup.
3. Run staging mobile recovery against the deployed endpoint.
4. Confirm no production release contains the proposed Nostr backup format. If
   one does, stop and add a legacy migration phase rather than silently
   abandoning its data.
5. Merge the GETPAID-2 stack in order under normal required checks.
6. Do not close or delete the original Nostr PRs until the product decision to
   supersede them is explicit.
7. Retain archive refs even after GETPAID-2 merges.

## Three-Hour Execution Target

This is an aggressive agent wall-clock target, not a promise that hosted CI and
human review finish in three hours.

| Time | Agent A | Agent B | Agent C | Agent D |
| --- | --- | --- | --- | --- |
| 0:00-0:15 | Server worktree and migration | PR15 worktree and key paths | Archive metadata WIP and worktree | Freeze manifests, refs, and fixtures |
| 0:15-1:20 | API, DB, auth, tests | Replacement PR16-24 commits | Metadata PR46-49 commits | Integration fakes and replay preparation |
| 1:20-2:05 | Server verification/fixes | Focused keychain verification | Focused metadata verification | Replay PR25-45 onto replacement PR24 |
| 2:05-2:30 | Cross-contract fixes | Integration fixes | Cherry-pick metadata onto PR45 | Generate files and assemble PR49 tip |
| 2:30-2:55 | Final server suite | Mobile failures by ownership | Mobile failures by ownership | Full mobile tip suite and structural checks |
| 2:55-3:00 | Push server branch | Hand off final commits | Hand off final commits | Push branches and create draft PRs |

Hosted CI may continue after hour three. Significant source-stack movement,
schema-generation failures, or broad conflicts in PR24/PR33 can extend the
active work.

## Stop Conditions

Stop rather than papering over the problem when:

- the source Nostr stack cannot be recovered from remote archive refs;
- mobile and server disagree on signed bytes or ETag vectors;
- a production release already wrote Nostr backups and no migration decision
  exists;
- the 1,000-label fixture exceeds the 2 MiB ciphertext limit;
- Bullnym accepts stale writes or stale deletes;
- recovery failure blocks access to the seed-derived wallet;
- metadata recovery enables publication or creates wallets;
- the final tree still contains backup relay connections;
- a generated migration/schema mismatch cannot be explained;
- a tip-only fix knowingly leaves an ancestor broken.

## Completion Criteria

The work is complete when:

- the original Nostr stack and metadata checkpoint remain remotely accessible
  and unchanged;
- Bullnym's opaque blob API is implemented, tested, and deployable;
- GETPAID-2 branches 01-49 form one valid independent chain;
- PR16-24 contain the Bullnym keychain replacement and no relay backup path;
- PR25-45 preserve the intended later Get Paid behavior;
- PR46-49 implement one-blob metadata publication and automatic non-blocking
  recovery;
- the final mobile tip passes the full validation suite;
- every intermediate branch passes structural validation and is queued for
  normal required CI before merge;
- all branch mappings, conflict adaptations, fixtures, and deployment order are
  documented.
