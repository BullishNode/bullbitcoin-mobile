# Deterministic Wallets

Deterministic Wallets owns reusable wallet materialization from reserved BIP85
child mnemonics. It is product-neutral: BTCPay/SamRock is the first consumer,
and future products can reuse the same public facade when they need the same
reserved-index materialization behavior.

## Scope

- Accept caller-provided wallet specs. There is no template registry in this
  feature.
- Derive the requested BIP85 child mnemonic from the default wallet at the
  caller-provided reserved index and alias.
- Create or reuse the requested wallets after verifying deterministic wallet
  descriptors for existing wallet IDs.
- Store the child seed only when at least one requested wallet must be created.
- Expose rollback for wallets created before an external product submits or
  persists descriptors. This remains a public compensation operation for
  best-effort local cleanup before a consumer starts remote descriptor
  submission.

## Boundaries

- Other features may only consume
  `public/deterministic_wallets_facade.dart`.
- Product policy lives with the consuming feature or a feature-owned public
  policy boundary. For example, BTCPay consumes the BIP85 registry reservation
  `39'/0'/12'/100'` and supplies Bitcoin and Liquid wallet specs, labels, sync
  behavior, and whether wallets are default wallets.
- The feature does not own auto-sweep, hide-on-home, wallet display settings,
  payment products, Nostr, SamRock, or BTCPay connection state.
- The feature does not automate recovery; recovery ownership remains outside
  this feature.

## Public Contract

`DeterministicWalletsFacade.prepare()` accepts a
`DeterministicWalletsRequest` with a BIP85 child mnemonic index, alias,
environment, and explicit wallet specs. The request must have a non-negative index,
non-empty alias, at least one wallet spec, and unique non-empty spec IDs.

The facade returns prepared deterministic-wallet DTOs containing wallet IDs,
network/script metadata, labels, public descriptors, creation flags, and
rollback metadata. It does not expose mnemonic words, seed bytes, or child seed
objects to consuming features. Rollback is performed by passing the prepared
result back to `rollbackCreatedWallets()`.

## Layers

- `domain/`: request, wallet spec, prepared wallet DTOs, feature errors, and
  `PrepareDeterministicWalletsUsecase` orchestration.
- `domain/repositories/`: deterministic wallet repository contract consumed by
  the use case.
- `data/`: implementation that wraps core wallet/seed repositories, derives
  expected metadata, verifies existing wallet descriptors, and maps core wallet
  entities to deterministic wallet result DTOs.
- `public/`: facade used by BTCPay and future products. It exports only
  published domain request/result/error types. Its constructor is a DI/testing
  surface and accepts the internal use case.
- `deterministic_wallets_locator.dart`: DI registration after core BIP85,
  wallet, and seed repositories are available.

## Flow

1. The caller builds product policy as wallet specs.
2. The use case derives the BIP85 child mnemonic for the requested reserved
   index.
3. Expected wallet metadata is derived from the child seed.
4. Existing wallet IDs are reused only if descriptors and script type match.
5. Missing wallets trigger child seed storage and wallet creation.
6. If an external product fails before descriptor submission, rollback deletes
   only wallets created by that attempt and deletes the child seed only when it
   was stored by that attempt and no wallet was reused.

## Future Consumers

Future products should add a small feature-owned request builder that maps their
business policy to `DeterministicWalletsRequest`. If several products later
share the same policy, extract the duplication only then; do not add a global
template registry preemptively.
