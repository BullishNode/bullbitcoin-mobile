# Keychain Recovery Architecture

## Scope

`keychain_recovery` restores supported wallet materializations from validated `keychain_manifest` import plans.
Its domain use case coordinates local wallet creation/reuse through deterministic wallet public APIs and records restored materializations through `keychain_manifest/public`; its data implementation adapts deterministic wallet materialization.

It does not decode manifest files, own manifest persistence, publish or fetch remote manifests, submit product descriptors, mark product accounts connected, or expose UI.

V1 recovery supports wallet materializations whose reservation is already
manifest-enabled and verified Nostr-key materializations.
BTCPay and Lightning Address wallet materializations can be recovered locally.
Nostr keys are recovered by re-deriving and verifying their public key, then
recording the local materialization. No private key is persisted during this
process.

Which reserved seeds are exportable vs recoverable at this stack level is the
`KeychainManifestReservationSupport` classification (`supportsV1Export` vs
`supportsV1Recovery`): 100/101/102 are exported into the backup, while BTCPay
(100) and Lightning Address (101) are locally recoverable here. Payment Page
(102), and later POS, become recoverable only in their owning product PRs.
`remote_keychain_recovery` consumes successful reactivation outcomes and asks
the owning product facade to verify/heal server state.

## Boundaries

- `keychain_manifest` owns manifest records, file encode/decode validation, and import plans.
- `bip85_registry` owns reserved derivation aliases used to reproduce product BIP85 children without importing product features.
- `keychain_recovery` owns local wallet materialization restore orchestration.
- `deterministic_wallets` owns BIP85 child mnemonic wallet creation/reuse.
- Product features own product state.
Restoring a BTCPay wallet materialization restores local wallets only; it does not restore SamRock pairing.
Restoring a Lightning Address wallet materialization restores local wallets only; its reservation is marked as `requiresProductReactivation` because Bullnym registration must be checked or recreated by Lightning Address.

Allowed dependencies:

- `keychain_recovery -> keychain_manifest/public`
- `keychain_recovery -> bip85_registry/public`
- `keychain_recovery -> deterministic_wallets/public`
- `keychain_recovery -> core/settings`
- `keychain_recovery -> core/nostr` (deterministic public-key re-derivation and
  verification; no secret material crosses the recovery result boundary)
- `keychain_recovery -> core/wallet` (re-applies the locked hidden + autosweep
  Get Paid posture to restored wallets via ApplyWalletBehaviorDefaultsUsecase -
  decision [1]/[C]/KC-6)

Forbidden dependencies:

- `keychain_manifest -> keychain_recovery`
- `keychain_recovery -> btcpay`
- `keychain_recovery -> get_paid`
- `keychain_recovery -> UI features`

## Result Model

Restore returns one outcome per wallet materialization:

- `created`
- `alreadyPresent`
- `requiresProductReactivation`
- `skippedUnsupported`
- `failedParentFingerprintMismatch`
- `failedChildSeedFingerprintMismatch`
- `failedInvalidImportPlan`
- `failedWalletCreation`
- `failedManifestRecord`
- `failedConflict`
- `skippedTimeBudgetExpired`

Unsupported wallet networks do not invalidate the whole manifest file or the whole entry; supported wallet materializations continue and unsupported ones are reported per wallet.
Invalid manifest file structure, duplicate wallet materializations, and reservation mismatches are rejected before recovery by `keychain_manifest`.
Because import-plan DTOs cross a public facade boundary, `keychain_recovery` also revalidates reservation identity, derivation path, entry identity, and wallet membership before materializing wallets.

`requiresProductReactivation` is a successful local wallet restore with a required follow-up product activation step.
Lightning Address uses this status because manifest recovery restores the wallet materialization but not Bullnym registration state.
Each outcome also retains whether the wallet was newly created, independently
of its status, so a newly created wallet that requires product reactivation is
not lost from later recovery coordination.

The caller may provide an absolute deadline. Recovery checks it before each
manifest entry and reports the remaining entry materializations as
`skippedTimeBudgetExpired` instead of starting more derivation work. Dart
futures are not cancellable, so an already-started materialization may finish;
no later entry is started after the deadline.

Once a wallet materialization is returned as `created`, `alreadyPresent`, or `requiresProductReactivation`, it is treated as current local wallet inventory.
If manifest recording then fails, recovery returns `failedManifestRecord` for those wallets and rolls back newly created deterministic wallets best-effort when the materializer supplies a rollback callback.
Rollback is only allowed inside the deterministic wallet materializer or through its explicit rollback callback; keychain recovery never edits manifest files directly.
Successful restore inventory is recorded through
`KeychainManifestFacade.recordRecoveredDerivation`, keeping its origin
distinct from a new local materialization so automated backup publication can
ignore recovery-originated writes.
