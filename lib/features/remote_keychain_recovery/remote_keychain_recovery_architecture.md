# Remote Keychain Recovery Architecture

## Scope

`remote_keychain_recovery` orchestrates the user-visible recovery sequence for encrypted Nostr backups. It recovers Get Paid deterministic wallets from the keychain manifest first, heals the recovered products, then automatically discovers and applies the independent wallet-metadata snapshot. It owns flow ordering and presentation state, but it does not own either wire protocol, relay transport, key derivation, metadata contributor stores, wallet materialization, product activation, relay policy, or backup activation.

Keychain manifest and wallet metadata remain separate backup products. They have different Nostr authors, encryption keys, activation and publication-acknowledgement state, payloads, publication state, and recovery outcomes. This flow coordinates them without merging their cryptographic or persistence contracts.

## Recovery Order

Keychain-manifest recovery runs first because wallet metadata has no authority to create wallets. The manifest check selects an authenticated latest candidate, reports an older candidate for explicit approval, or surfaces no-manifest, unavailable, unrecoverable, and update-required outcomes distinctly. A selected import plan is materialized through `keychain_recovery`, and each successful wallet outcome records whether that wallet was created in this run even when the product also requires reactivation.

The flow runs product healing after keychain materialization. Lightning Address, Payment Page, and Point of Sale healing remain owned behind their public facades. The cubit renders the resulting liveness/partial outcomes and never reaches into product internals.

Wallet-metadata recovery starts automatically after the keychain phase, including when no Get Paid manifest exists or the user declines or skips the separately disclosed keychain stream. Relay fetch produces an internal validated plan, and a valid plan is applied without a second confirmation. The remote feature's use cases map wallet-metadata failures at the facade boundary, so its cubit sees only this feature's recovery failure family plus the facade's published result types. Apply receives only the exact wallet references reported as newly created by keychain recovery; pre-existing and absent wallets therefore follow the metadata feature's preserve/defer policy. If no metadata snapshot exists, the original keychain result remains on screen rather than being replaced by a lower-priority absence message.

## Consent

Keychain-manifest relay disclosure uses the same persisted acknowledgement as Get Paid automated-backup creation. `start()` combines that acknowledgement with an explicit acceptance, so consent already given for that exact backup stream is honored during recovery.

Wallet metadata recovery has no separate disclosure or persisted authorization gate. Seed recovery derives the separate metadata identity and checks policy relays automatically. This lookup does not enable metadata publication, acknowledge its publication disclosure, or alter keychain-manifest consent or activation.

## Publication Discipline

Keychain recovery and healing run inside a wallet-metadata publication-suppression scope. Wallet creation or product-default writes may mark metadata dirty, but they cannot race an automatic metadata snapshot onto relays before remote metadata is checked and applied. The same scope is reused by automatic metadata recovery and closes when metadata reaches a terminal outcome or the cubit is disposed. This also closes the app-resume window between wallet materialization and metadata discovery.

After a latest keychain-manifest restore, the keychain backup may republish through its existing consent/toggle/empty chokepoint. After an explicitly approved older manifest restore it does not republish, because a fresh replaceable event could overwrite a newer manifest this binary could not recover. Unsupported, absent, unavailable, skipped, and failed manifest outcomes also do not republish.

A metadata-recovery session holds metadata publication suppression from keychain materialization, when applicable, or otherwise from the initial metadata lookup through apply, terminal result, failure, or cubit disposal. Metadata planning and apply never publish. A latest complete metadata apply records the selected head locally as verified; older or incomplete apply persists a protective publication block. Later user changes can publish only through the normal metadata backup chokepoint.

## Boundaries

Allowed feature dependencies are:

- `remote_keychain_recovery -> keychain_manifest/public`
- `remote_keychain_recovery -> keychain_recovery/public`
- `remote_keychain_recovery -> wallet_metadata_backup/public`
- `remote_keychain_recovery -> nostr_relay_policy/public`
- `remote_keychain_recovery -> get_paid_settings/public`
- `remote_keychain_recovery -> lightning_address/public`
- `remote_keychain_recovery -> payment_page/public`
- `remote_keychain_recovery -> pos/public`
- `remote_keychain_recovery -> core/*`

Every facade call is wrapped in a `remote_keychain_recovery/domain/usecases` use case. The cubit calls only those use cases and stores only public contract types needed to continue the flow. Direct imports from another feature's `domain`, `data`, or `presentation` folders are forbidden.

## Outcome Contract

Every produced check, restore, heal, apply, failure, and update-required status has a terminal or retryable UI. An older keychain-manifest choice is never implicit; the metadata feature may automatically apply its best authenticated complete snapshot under its additive and preserve-local policies. Metadata apply reports restored, already-present, preserved-conflict, deferred, unsupported, invalid, and failed-storage counts separately; any divergence or protective block becomes `metadataPartiallyRestored` rather than a false success.

Relay, codec, and storage details are logged at their owning boundaries and collapse into typed/sanitized outcomes before presentation. No xprv, seed material, plaintext metadata, record id, ciphertext, or raw transport error may enter cubit state or user-facing copy.
