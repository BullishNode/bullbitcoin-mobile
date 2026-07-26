# Remote Keychain Recovery Architecture

## Scope

`remote_keychain_recovery` is the application orchestrator for restoring the
keychain-manifest section of the single Bull `wallet_backup` object.

It:

- fetches the validated manifest DTO through `wallet_backup/public`;
- reparses it through `keychain_manifest/public`;
- materializes supported wallets through `keychain_recovery/public`;
- asks owning product facades to heal server state after local restoration;
- returns a feature-owned result suitable for silent onboarding recovery.

At this stack level, Lightning Address is the only Bullnym-backed product whose
wallet reservation and healing flow both exist. Later product-owning PRs extend
the reservation classification and healer without changing the remote backup
contract.

It does not own encryption, remote transport, manifest parsing rules,
deterministic wallet creation, product registration protocols, metadata
recovery, settings UI, or backup publication.

## Dependencies

```text
remote_keychain_recovery
  -> wallet_backup/public
  -> keychain_manifest/public
  -> keychain_recovery/public
  -> lightning_address/public
```

Section owners do not import this feature. The orchestrator publishes only its
own result model and does not expose `WalletBackupFailure`,
`KeychainManifestImportPlan`, or product-specific healing types.

## Ordered Recovery

Recovery proceeds in this order:

1. Fetch and authenticate the unified remote object.
2. Distinguish an absent object from a present canonical empty manifest.
3. Reparse the feature-owned payload DTO through the manifest facade.
4. Restore supported local wallet materializations.
5. Record restored inventory as recovery-originated.
6. Heal applicable product registration state.
7. Return counts and created wallet ids.

Onboarding awaits this bounded operation after the default wallets and physical
backup verification are complete, but before signalling success. That ensures
restored product wallets exist before the first wallet inventory load.
The onboarding wrapper logs sanitized non-success status and never lets optional
remote recovery prevent seed recovery.

RecoverBull follows the same ordering after restoring its default wallets:
its feature-owned wrapper awaits optional remote recovery before dispatching
`WalletStarted`, and swallows/logs sanitized failures so an unavailable backup
does not prevent the vault recovery from finishing.

Recovery never enables backup, marks a user consent flag, publishes, deletes, or
changes remote checkpoint state.

## Deadline

One 60-second wall-clock budget starts before lifecycle-lease acquisition and
covers remote checkpoint reads, keychain materialization, metadata application,
final checkpoint revalidation, and product healing. Read-only remote calls use
their remaining time. Keychain and metadata recovery receive the same absolute
deadline and do not start another local mutation after it expires. Lightning
Address, Donation Page, and Point of Sale healing all share that deadline;
recovery never starts re-registration.

Dart futures are not cancellable. An already-started read-only request may
finish after the caller receives `timedOut`. Once local mutation starts, the
caller awaits it to settle before releasing the unified-backup recovery lease;
cooperative checks ensure no later recovery step is then started.

## Outcomes

The feature distinguishes:

- no remote backup;
- a present manifest with nothing to restore;
- unavailable, invalid, oversized, newer-version, and conflict failures;
- local failures;
- complete or partial restoration;
- deadline expiry.

A malformed reparsed DTO fails closed. A partial restoration preserves
successfully materialized wallets and reports the failed count for diagnostics.
Deadline expiry takes status precedence over partial restoration while retaining
the successful and failed counts and created wallet ids. Product healing is best
effort and does not roll back valid local wallets; a healing deadline expiry is
still reported as `timedOut`.

## Non-goals

- wallet-metadata recovery before the metadata section exists;
- compatibility with pre-release backup streams;
- retries or background scheduling;
- a user-visible recovery wizard in this PR;
- generic product-healer registration;
- cancellation claims for already-started Dart futures.
