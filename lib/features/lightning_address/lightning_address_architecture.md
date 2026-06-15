# Lightning Address

Lightning Address owns app-side orchestration for registering, deleting, checking, and activating the active Bullnym registration for a wallet identity.

## Scope

This PR owns:

- the public Lightning Address facade;
- domain use cases for prepare wallet, register, delete, lookup/status, wallet-owned registration/status composition, wallet-owned activation composition, and receive-readiness lookup;
- deterministic Liquid receive wallet materialization through the Deterministic Wallets facade;
- keychain manifest metadata recording through the Keychain Manifest facade;
- Lightning Address receive-wallet behavior defaults so the Liquid receive wallet is hidden on Home and eligible for generic autosweep;
- mapping Bullnym failures into Lightning Address domain errors;
- routed activation/status UI under Bitcoin settings, including local receive-readiness status;
- localized Lightning Address domain and activation copy, documentation, and feature graph edges;
- headless Bullnym, Nostr Identity, and Lightning Address dependency-injection locators so the facade and activation UI are production-composable.

It does not own public identity registration, payment pages, wallet manifest publish, Nostr relay/profile/DM behavior, autosweep execution, registration-state persistence, delete/replace UI, or payment-page receive flows.

## Boundaries

Lightning Address consumes only public facades:

- `features/bullnym/public/bullnym_facade.dart`;
- `features/deterministic_wallets/public/deterministic_wallets_facade.dart`;
- `features/keychain_manifest/public/keychain_manifest_facade.dart`;
- `features/nostr_identity/public/nostr_identity_facade.dart`.

It does not import Bullnym internals, Bullnym signing helpers, Bullnym HTTP adapters, or raw Nostr derivation paths.
Registration and delete derive the Bullnym server-auth public key and signing operation through the role-named Nostr Identity facade methods.

Registration and delete receive `xprvBase58` only as point-of-use method input so Lightning Address can build a one-shot Bullnym auth signer through Nostr Identity.
They pass the confidential descriptor through to Bullnym registration.
Lookup accepts the Bullnym auth public key/npub hex and does not require wallet secret material.
Lightning Address does not persist or own wallet secrets.
It delegates local wallet creation/reuse to Deterministic Wallets, records recovery metadata through Keychain Manifest, and only handles returned public descriptors for Bullnym registration.

`prepareWallet()` creates or reuses the dedicated Liquid receive wallet from the `lightning_address_wallet_seed` BIP85 reservation, records the resulting wallet materialization in the keychain manifest, and applies product defaults through the generic wallet behavior use case: `hideOnHome: true` and `autoSweepEnabled: true`.
Lightning Address applies those defaults because it owns the product policy, but it does not run sweeps itself.
Actual drain execution remains in `features/autosweep` and is triggered by the wallet sync flow when the synced wallet has autosweep enabled.
If manifest recording or defaults fail after local wallet creation, the use case rolls back newly created deterministic wallets best-effort and returns a local preparation error.
Recovered Lightning Address wallets require product reactivation because the manifest can restore wallet materialization metadata but cannot prove an active Bullnym server registration.

The existing `xprvBase58` and confidential descriptor registration inputs remain foundation inputs for internal protocol use cases.
They are not exported by the public facade and must not be passed from routed UI.
`RegisterWalletOwnedLightningAddressUsecase` is the product-safe registration composition point: it accepts only a nym, rejects blank nyms before local side effects, derives the default-wallet xprv behind a Lightning Address port, prepares or reuses the dedicated Liquid wallet, and submits the prepared wallet's confidential descriptor through the protocol registration use case.
`LookupWalletOwnedLightningAddressRegistrationUsecase` is the matching product-safe status path; it derives the same wallet-owned auth material internally, derives the Bullnym auth public key, and returns Bullnym's nym/active status without exposing xprv input.

If local default-wallet xprv derivation or wallet preparation fails, no Bullnym registration is attempted.
If Bullnym registration fails after wallet preparation, the wallet-owned registration use case throws `WalletOwnedLightningAddressRegistrationException` with the prepared wallet id, whether it was created in the attempt, and whether the failure is an uncertain post-submission transport/response failure.
Lightning Address keeps the prepared deterministic wallet and local manifest entry for retry/status reconciliation; it does not invent rollback semantics for a request that may have reached the server.

The routed activation/status UI lives under Bitcoin settings.
Its Cubit depends on `ActivateWalletOwnedLightningAddressUsecase` and `LookupLightningAddressReceiveReadinessUsecase`.
The activation use case maps wallet-owned registration failures to an activation-safe Lightning Address exception that keeps wallet-id metadata out of the presentation contract while preserving local-preparation versus uncertain post-submission failure semantics.
The readiness use case combines the wallet-owned Bullnym status lookup with local receive-wallet preparation only when the server registration is active, so an active server registration can repair local receive readiness without exposing wallet metadata to the UI.
The UI can submit a nym after explicit consent, show an active nym from lookup, show whether the local receive wallet is ready for receive/autosweep, show the server-returned Lightning Address only after a fresh registration response, and surface lookup failures separately from inactive status.
It does not pass xprv material, descriptors, wallet ids, Nostr handles, Bullnym internals, autosweep internals, or raw protocol use cases through presentation or route state.

Lookup currently reflects the Bullnym public lookup contract: it reports the registered nym and whether it is active.
It does not synthesize a copyable Lightning Address from a hardcoded domain.
Canonical display/copy address after lookup belongs in a later backend/facade contract or wallet/config-owned flow.

The local nym validation owned here rejects empty or whitespace-only values and full-address input containing `@` before key derivation and network calls.
Character sets, case policy, length limits, reserved names, and normalization remain Bullnym protocol or product decisions.
