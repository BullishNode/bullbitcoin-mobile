# QA overlay notes (WP-A1, 2026-07-17)

Test-only notes for this overlay branch (`qa/getpaid-cert-0e02d5a18`, based on
PR #132 provisional tip `0e02d5a18a32efb76b8b4a439555d0d42744c119`). Not
product documentation — see `getpaid-e2e-phaseA-A1-overlay-2026-07-17.md` in
the workspace root for the full WP-A1 report.

## EXCLUDED — `fake_nostr_relay.dart` (superseded architecture)

The old `qa/e2e-matrix-rc-f6eec51` overlay's `integration_test/support/`
carried a `FakeNostrRelay` test double plus a `KeychainManifestNostrRelayRepository`
locator override, used to puppet a raw Nostr relay WebSocket connection for
keychain-manifest backup/recovery tests.

At the current PR #132 tip, **both** the keychain-manifest and
wallet-metadata-backup remote repositories (`BullnymKeychainManifestRemoteRepository`,
`BullnymWalletMetadataRemoteRepository`) go exclusively through
`BullnymClientPort.fetchBackup/storeBackup/deleteBackup` — there is no longer
a direct Nostr relay connection anywhere in the backup/recovery path for the
client to fake. `fake_nostr_relay.dart` and the old
`KeychainManifestNostrRelayRepository`-based override were therefore **not
ported**: there is no product surface left for them to attach to.
`test_locator_overrides.dart` was rewritten to override `BullnymClientPort`
only.

## RESOLVED — `integration_test/qa_matrix/*` (pubspec fence)

`qa_matrix/support/scenario_compiler.dart`, `invariant_assertions.dart`,
`recovery_status_mapping.dart`, `matrix_runner.dart`, `matrix_fixtures.dart`,
`named_case.dart`, and the three `qa_matrix_*_test.dart` files were ported and
adapted (see the WP-A1 report for the full list of adaptations), and the
`packages/qa_matrix_engine` pure-Dart package was copied into this overlay
unchanged.

This was previously **BLOCKED** because `qa_matrix_engine` was not a
workspace member / dev_dependency of this overlay's `pubspec.yaml` — every
file that imports `package:qa_matrix_engine/qa_matrix_engine.dart` failed
with `uri_does_not_exist`. An owner decision authorized the same dev-only
wiring the old overlay used: a `workspace:` entry for
`packages/qa_matrix_engine` plus a `qa_matrix_engine:` `dev_dependencies:`
entry in `pubspec.yaml`, both dev-only with zero build/APK impact (no `lib/`
file imports `qa_matrix_engine`; the entry lives only under
`dev_dependencies:`, never `dependencies:`).

With the wiring in and `flutter pub get` re-run, `dart analyze
integration_test/qa_matrix packages/qa_matrix_engine` is **clean — 0
issues** (previously 142, all `uri_does_not_exist`/`undefined_*` fallout from
the missing package, not defects in the ported/adapted code).

## Best-effort, unverified adaptation — `scenario_compiler.dart`

Beyond the pubspec fence, `scenario_compiler.dart` needed a structural rewrite
because the `RemoteKeychainRecoveryCubit`/`RemoteKeychainRecoveryState` it
drove is gone (recovery is now one synchronous
`RemoteKeychainRecoveryFacade.recover()` call, no relay-consent gate). The
D3 (manifest-integrity fault) and D4 (relay-transport fault) dimensions it
used to drive via `FakeNostrRelay` hooks (tamper/forge/timeout/flood/
size-cap/offline) have **no equivalent fault-injection surface on
`FakeBullnymClient` today**; rather than invent one unreviewed on a
money-adjacent test double, every cell in those two dimensions now raises
`ScenarioUnsupported`. Likewise the D7 interrupt dimension (mid-recovery
cancel) has no seam now that recovery is a single synchronous call, and the
`err-500`/`err-conflict`/`err-ratelimited` server-fault cells relied on an
`injectedRegistrationError` field `FakeBullnymClient` no longer has. **This
whole file is unverified end-to-end** (it cannot be `dart analyze`d until the
pubspec fence above is resolved) and should get a dedicated Fable pass before
any of it is trusted, per the money-safety-critical program's gate.
