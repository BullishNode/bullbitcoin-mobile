# 14-PR Architecture Refactor Plan

This plan rebuilds the stacked Get Paid / BTCPay / Keychain Manifest / Bullnym /
Lightning Address branches against the current architecture target in
`ARCHITECTURE.md`.

The target architecture is the consolidated feature spine:

```text
ui -> presentation -> domain/usecases -> domain/repositories -> data -> datasource
```

The stack must converge away from the heavier hexagonal folders:

```text
application/
frameworks/
adapters/
interface_adapters/
```

Those names may exist in unrelated legacy code, but this stack is new code and
must not preserve them as the target architecture.

## Source Of Truth

Read docs in this order before each gate:

1. `ARCHITECTURE.md`
2. `AGENTS.md`
3. `FEATURES.md`

If a feature-local architecture doc disagrees with repo-level
`ARCHITECTURE.md`, the feature doc is stale and must be updated in the same
gate as the code.

## Stack Order

The local worktree stack is:

```text
PR1  bip85-registry-foundation
PR2  btcpay-registry-integration
PR3  keychain-manifest-btcpay-entries
PR4  keychain-manifest-file-contract
PR5  keychain-manifest-file-import
PR6  keychain-recovery-wallet-restore
PR7  getpaid-reservation-registry
PR8  nostr-core
PR9  bullnym-protocol-foundation
PR10 lightning-address-foundation
PR11 lightning-address-wallet-materialization
PR12 lightning-address-wallet-owned-registration
PR14 lightning-address-activation-ui
PR13 lightning-address-autosweep-readiness
```

PR14 is intentionally listed before PR13 because the top-stack history has the
activation UI commits below the autosweep-readiness commits.

## Global Refactor Rules

Apply these rules to every stack-authored feature:

- `application/usecases/` becomes `domain/usecases/`.
- Storage/retrieval abstractions become
  `domain/repositories/<noun>_repository.dart`.
- External action/service abstractions with no entity ownership become
  `domain/<capability>_port.dart`.
- `frameworks/` implementations become `data/` implementations.
- HTTP, Drift, secure-storage, or SDK wrappers live in `data/datasources/` only
  when a repository implementation wraps them.
- Repository implementations live directly under `data/`; do not create
  `data/repositories/`.
- Wire or persistence shapes live in `data/models/`.
- Mapping between models and entities lives in `data/mappers/` once non-trivial.
- One sealed error family lives at `domain/<feature>_error.dart`.
- Public facades are concrete classes and the only cross-feature entry point.
- Public facades must not export `application/`, `data/`, `frameworks/`,
  `presentation/`, or `ui/` types, except narrow route/UI exports that are
  intentionally the public route contract.
- Presentation imports use cases and domain/published error types only. It must
  not import repositories, datasources, or another feature's internals.
- Feature architecture docs must describe the same shape as the code.

## Public Contract Inventory

The public facade cleanup is the highest-priority work because later PRs build
on these contracts.

### `bip85_registry`

Current target:

- `domain/bip85_reservation.dart`
- `domain/bip85_reservations.dart`
- `public/bip85_registry_facade.dart`

Expected public contract:

- reserved-path policy and lookup methods only
- no runtime wallet state
- no product feature imports

### `deterministic_wallets`

Current drift:

- `application/prepare_deterministic_wallets_usecase.dart`
- `application/application_errors.dart`
- `public/deterministic_wallets_facade.dart` exports application errors

Target:

- `domain/usecases/prepare_deterministic_wallets_usecase.dart`
- `domain/deterministic_wallets_error.dart`
- `public/deterministic_wallets_facade.dart` exports only published domain or
  public request/result types

Decision required during Gate B:

- Decide whether rollback is a public deterministic-wallet operation or an
  internal compensation detail that belongs in higher-level feature use cases.

### `keychain_manifest`

Current drift:

- `application/ports/keychain_manifest_entry_store.dart`
- `application/usecases/*`
- `application/keychain_manifest_file_codec.dart`
- `application/application_errors.dart`
- `domain/domain_errors.dart`
- `frameworks/drift_keychain_manifest_entry_store.dart`
- public facade imports application commands, codec, and errors

Target:

- repository contract in `domain/repositories/`
- use cases in `domain/usecases/`
- Drift persistence in `data/`
- serialization/model/mapping in `data/` when needed
- one `domain/keychain_manifest_error.dart`
- facade publishes stable request/result types only

### `keychain_recovery`

Current drift:

- `application/restore_keychain_manifest_wallets_usecase.dart`
- `application/ports/keychain_recovery_wallet_materializer_port.dart`
- `frameworks/deterministic_wallet_recovery_materializer.dart`
- public facade imports the application use case

Target:

- restore use case in `domain/usecases/`
- wallet materializer capability port in `domain/`
- deterministic materializer implementation in `data/`
- facade exports recovery result/public error types only

### `nostr_identity`

Current drift:

- `application/derive_nostr_identity_handle_usecase.dart`
- public facade imports the application use case

Target:

- derive use case in `domain/usecases/`
- facade exposes role-named methods only
- no raw path/index API in public contract

### `bullnym`

Current drift:

- `application/usecases/*`
- `application/ports/bullnym_client_port.dart`
- `application/application_errors.dart`
- `frameworks/bullnym_http_client.dart`
- public facade exports application errors

Target:

- use cases in `domain/usecases/`
- `BullnymClientPort` in `domain/`
- HTTP client in `data/`
- one `domain/bullnym_error.dart`
- facade exports stable Bullnym result types only

### `autosweep`

Current drift:

- `application/run_auto_sweep_usecase.dart`
- `application/autosweep_fee_policy.dart`
- `application/ports/autosweep_wallet_port.dart`
- `frameworks/autosweep_wallet_adapter.dart`
- feature architecture doc describes application/frameworks as target

Target:

- use case in `domain/usecases/`
- fee policy in `domain/` if it is product policy
- wallet capability port in `domain/`
- adapter in `data/`
- facade imports domain use case only

### `btcpay`

Current drift:

- `application/usecases/*`
- `application/ports/btcpay_connection_store.dart`
- `application/ports/samrock_pairing_service_port.dart`
- `application/application_errors.dart`
- `frameworks/datasources/*`
- presentation imports application errors and use cases
- feature architecture doc describes application/frameworks as target

Target:

- use cases in `domain/usecases/`
- `BtcpayConnectionStore` becomes
  `domain/repositories/btcpay_connection_repository.dart`
- secure storage implementation becomes `data/btcpay_connection_repository_impl.dart`
- SamRock capability port moves to `domain/`
- SamRock HTTP implementation moves to `data/`
- one `domain/btcpay_error.dart`
- public route contract remains narrow

### `lightning_address`

Current drift:

- `application/usecases/*`
- `application/ports/lightning_address_default_wallet_xprv_port.dart`
- `application/application_errors.dart`
- `frameworks/default_wallet_xprv_adapter.dart`
- public facade exports application errors and use-case command/result types
- presentation imports application errors and use cases

Target:

- use cases in `domain/usecases/`
- default-wallet xprv capability port in `domain/`
- xprv adapter in `data/`
- one `domain/lightning_address_error.dart`
- public facade publishes stable request/status/result types only
- presentation imports domain use cases and domain errors only

## Gate And Review Loop

Every gate uses this loop:

```text
1. Implement the gate scope.
2. Run gate checks.
3. Run architecture review.
4. Fix every fix-now architecture finding.
5. Re-run architecture review.
6. Repeat until no fix-now architecture findings remain.
7. Run the full 7-agent review at the gate boundary.
8. Fix every full-review fix-now finding.
9. Re-run the full 7-agent review.
10. Repeat until no full-review fix-now findings remain.
11. Run final gate checks.
12. Commit the gate work.
13. Rebase the next dependent branch onto the committed gate branch.
```

Findings may be left only as `defer-with-reason`, and the reason must explain
why later PRs can safely build on the code without locking in the wrong
architecture.

## Full 7-Agent Gate Reviews

Run a full review after roughly every five plan items and at every hard gate.
The seven roles are:

1. `ARCHITECTURE.md` architecture
2. AI-slop/evidence
3. Dart/Flutter code quality
4. UX/user-flow
5. over-engineering
6. deletion/scope-control
7. AGENTS.md compliance

The full review is still scoped to the gate's changes. It must not expand into
unrelated legacy cleanup.

## Commit Rule

After each review loop closes:

1. confirm no `fix-now` findings remain;
2. confirm any remaining findings are explicitly `defer-with-reason`;
3. run required checks;
4. commit the gate as an atomic commit or small commit set;
5. continue only after the commit succeeds.

Do not carry uncommitted reviewed work into the next gate.

## Rebase Rule

After each gate commit, rebase the next branch in the stack onto the just-cleaned
parent branch.

Conflict resolution must choose the architecture-compliant side:

- `domain/usecases`, not `application/usecases`
- `domain/repositories`, not `application/ports`, for storage/retrieval
- `domain/*_port.dart`, not `application/ports`, for capability ports
- `data/`, not `frameworks/`
- `domain/<feature>_error.dart`, not per-layer errors
- public facade request/result types, not application command classes
- repository/data mappers, not datasources returning domain entities
- feature docs matching `ARCHITECTURE.md`

## Gate Plan

### Gate A: Inventory And Contract Plan

Scope:

- create this inventory and refactor plan;
- verify it matches `ARCHITECTURE.md`, `AGENTS.md`, and `FEATURES.md`;
- commit the plan document.

No stack rebase is required for Gate A if this document remains only on the
top-stack branch.

### Gate B: BIP85 And Deterministic Wallets

Branches:

- PR1 `bip85-registry-foundation`

Tasks:

1. Keep `bip85_registry` as static reserved-path policy.
2. Move deterministic wallet use case to `domain/usecases/`.
3. Move deterministic wallet errors to `domain/deterministic_wallets_error.dart`.
4. Clean `public/deterministic_wallets_facade.dart` exports.
5. Remove feature use-case dependency on core data models where feasible.
6. Update `deterministic_wallets_architecture.md`.
7. Run review loop.
8. Commit.
9. Rebase the next dependent branch.

### Gate C: Keychain Manifest And Recovery

Branches:

- PR3 `keychain-manifest-btcpay-entries`
- PR4 `keychain-manifest-file-contract`
- PR5 `keychain-manifest-file-import`
- PR6 `keychain-recovery-wallet-restore`

Tasks:

1. Convert keychain manifest store to a domain repository.
2. Move keychain manifest use cases to `domain/usecases/`.
3. Move Drift implementation to `data/`.
4. Introduce data models/mappers only where persistence shape is non-trivial.
5. Merge keychain manifest errors into one domain error family.
6. Clean keychain manifest public facade.
7. Move keychain recovery use case to `domain/usecases/`.
8. Move recovery materializer port to `domain/`.
9. Move recovery materializer implementation to `data/`.
10. Clean keychain recovery public facade.
11. Update feature architecture docs.
12. Rebase PR4 onto PR3, PR5 onto PR4, and PR6 onto PR5 after each cleanup.
13. Run full gate review loop.
14. Commit each cleaned branch.

### Gate D: Nostr, Bullnym, AutoSweep, BTCPay

Branches:

- PR7 `getpaid-reservation-registry`
- PR8 `nostr-core`
- PR9 `bullnym-protocol-foundation`
- PR2 `btcpay-registry-integration`

Preferred rebuild order:

1. PR7 reservation policy.
2. PR8 Nostr Identity.
3. PR9 Bullnym.
4. AutoSweep in PR2.
5. BTCPay in PR2.

Tasks:

1. Ensure registry reservations remain static policy only.
2. Move Nostr Identity use case to `domain/usecases/`.
3. Clean Nostr Identity facade.
4. Move Bullnym use cases to `domain/usecases/`.
5. Move Bullnym client port to `domain/`.
6. Move Bullnym HTTP implementation to `data/`.
7. Merge Bullnym errors into one domain error family.
8. Move AutoSweep use case, policy, port, and adapter to target folders.
9. Convert BTCPay connection storage to a domain repository plus data impl.
10. Move SamRock capability port and HTTP implementation.
11. Merge BTCPay errors into one domain error family.
12. Clean BTCPay route/public surface.
13. Update feature architecture docs.
14. Rebase downstream branches after each cleaned branch.
15. Run full gate review loop.
16. Commit each cleaned branch.

### Gate E: Lightning Address Stack

Branches:

- PR10 `lightning-address-foundation`
- PR11 `lightning-address-wallet-materialization`
- PR12 `lightning-address-wallet-owned-registration`
- PR14 `lightning-address-activation-ui`
- PR13 `lightning-address-autosweep-readiness`

Tasks:

1. Move Lightning Address foundation use cases to `domain/usecases/`.
2. Merge Lightning Address errors into one domain error family.
3. Move validation to domain if it is use-case input/domain validation.
4. Clean Lightning Address public facade.
5. Move wallet materialization use cases to `domain/usecases/`.
6. Move default-wallet xprv port to `domain/`.
7. Move xprv adapter to `data/`.
8. Move wallet-owned registration/lookup use cases to `domain/usecases/`.
9. Convert public command/result types into stable public/domain types.
10. Move readiness use cases to `domain/usecases/`.
11. Ensure activation Cubit imports only domain use cases/errors and
    presentation state.
12. Update Lightning Address architecture docs.
13. Rebase PR11 onto PR10, PR12 onto PR11, PR14 onto PR12, PR13 onto PR14.
14. Run full gate review loop.
15. Commit each cleaned branch.

### Gate F: Final Stack Verification

Scope:

- all 14 PRs
- top-stack branch
- docs and feature graph

Tasks:

1. Verify every branch is based on its cleaned parent.
2. Verify PR14 is below PR13 in final stack order.
3. Verify `FEATURES.md` matches actual public-facade dependencies.
4. Verify no stack-authored feature reintroduces deprecated folders.
5. Verify no public facade exports internal layers.
6. Run required checks on the top-stack branch.
7. Run full 7-agent review loop.
8. Commit final docs or graph fixes.

## Architecture Greps

Run these after each gate and before final review:

```bash
rg -n "features/.*/application|features/.*/frameworks|features/.*/adapters|features/.*/interface_adapters" \
  lib/features/{bip85_registry,deterministic_wallets,btcpay,keychain_manifest,keychain_recovery,nostr_identity,bullnym,lightning_address,autosweep}

rg -n "export 'package:bb_mobile/features/.*/(application|data|frameworks|presentation|ui)/" \
  lib/features/*/public

rg -n "import 'package:bb_mobile/features/.*/(domain|data|application|frameworks|presentation|ui)/" \
  lib/features
```

The first grep should be empty for stack-authored deprecated folders after the
relevant feature gate completes. The third grep is not expected to be empty; use
it to inspect cross-feature internal imports.

## Required Checks

Use the makefile and pinned SDK:

```bash
make build-runner
make translations
make drift-migrations # only when Drift schema changes
make analyze
fvm dart fix --dry-run
make unit-test
```

Run narrower tests during a gate when useful, but do not mark a gate complete
until the required gate-level checks and review loops are clean.

